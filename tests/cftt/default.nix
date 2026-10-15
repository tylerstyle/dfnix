# CFTT-style write-blocking regression test (Phase 1a, module level).
#
# A builder VM creates dirty evidence disks (unreplayed ext4 journal, dirty XFS
# log, dirty NTFS, LUKS, RAID1 members, LVM, hibernation image). The host hashes
# the raw disk files, boots a VM with the dfnix write-blocking module and the
# forensic tools on the same files, exercises dfmount / dfdisk / dfnet / dfinfo,
# shuts it down and requires every evidence file to be bit-identical.
#
# dfdisk (0.2.0) is held to its exit codes, its .info.json reports and its audit
# records (the run's "started" and "finished" records, refusals, and the
# per-boot copy of the log in the case directory).
{ pkgs }:

let
  # Order defines the kernel names in both VMs (vda, vdb, ...). Sizes in MiB.
  disks = [
    { name = "ext4"; serial = "EVID-EXT4"; size = 64; evidence = true; }
    { name = "xfs"; serial = "EVID-XFS"; size = 300; evidence = true; }
    { name = "ntfs"; serial = "EVID-NTFS"; size = 64; evidence = true; }
    { name = "luks"; serial = "EVID-LUKS"; size = 64; evidence = true; }
    { name = "raid-a"; serial = "EVID-RAID-A"; size = 64; evidence = true; }
    { name = "raid-b"; serial = "EVID-RAID-B"; size = 64; evidence = true; }
    { name = "lvm"; serial = "EVID-LVM"; size = 64; evidence = true; }
    { name = "hiber"; serial = "EVID-HIBER"; size = 64; evidence = true; }
    { name = "target"; serial = "TARGET-01"; size = 1024; evidence = false; }
    { name = "target-lvm"; serial = "TARGET-LVM"; size = 128; evidence = false; }
    # Mounted read-only at /iso on the dfnix VM: a system disk for the registry
    { name = "system"; serial = "SYS-ISO"; size = 64; evidence = false; }
  ];

  # The VM start script expands $SHARED_DIR, a directory the test driver shares
  # between all machines of one test run, so both VMs attach the same files.
  drives = map (d: {
    name = d.name;
    file = ''"$SHARED_DIR"/cftt/${d.name}.img'';
    driveExtraOpts = {
      format = "raw";
      werror = "report";
    };
    deviceExtraOpts.serial = d.serial;
  }) disks;

  vmBase = {
    # tmpfs root: no root disk the write-blocking rule could lock, and no disk
    # besides the fixtures for anything to write to
    virtualisation.diskImage = null;
    virtualisation.qemu.drives = drives;
    boot.supportedFilesystems = [ "ntfs" "xfs" ];
  };

  makeFixtures = pkgs.writeShellApplication {
    name = "make-cftt-fixtures";
    runtimeInputs = with pkgs; [
      coreutils
      cryptsetup
      e2fsprogs
      gnugrep
      gptfdisk
      lvm2
      mdadm
      ntfs3g
      python3
      systemd
      util-linux
      xfsprogs
    ];
    text = builtins.readFile ./fixtures.sh;
  };

  diskList = builtins.toJSON (map (d: { inherit (d) name serial size evidence; }) disks);
in
pkgs.testers.runNixOSTest {
  name = "dfnix-cftt";

  nodes.builder = {
    imports = [ vmBase ];
    environment.systemPackages = [ makeFixtures ];
    virtualisation.memorySize = 2048;
  };

  nodes.machine = { pkgs, ... }: {
    imports = [
      vmBase
      ../../modules/hardware/write-blocking.nix
      ../../modules/hardware/protected-devices.nix
      ../../modules/release.nix
    ];
    virtualisation.memorySize = 2048;
    dfnix.release.revision = "cftt";

    # Like the live medium: read-only, and listed in the protected-device registry
    virtualisation.fileSystems."/iso" = {
      device = "/dev/disk/by-id/virtio-SYS-ISO";
      fsType = "ext4";
      options = [ "ro" "noload" ];
    };

    environment.systemPackages = with pkgs; [
      dfdisk
      dfmount
      dfnet
      dfinfo
      cryptsetup
      e2fsprogs
      lvm2
      polkit
    ];

    # Same examiner account shape as the live ISO: wheel member, no password
    users.users.nixos = {
      isNormalUser = true;
      extraGroups = [ "wheel" "disk" "storage" ];
    };
    security.polkit.enable = true;
    services.udisks2.enable = true;
  };

  testScript = ''
    import hashlib
    import json

    DISKS = json.loads(${builtins.toJSON diskList})
    EVIDENCE = [d for d in DISKS if d["evidence"]]
    BY_ID = {d["name"]: "/dev/disk/by-id/virtio-" + d["serial"] for d in DISKS}
    FIXTURES = builder.shared_dir / "cftt"
    EXAMINER = "cftt-examiner"


    def sha256(path):
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()


    def image(name):
        return FIXTURES / (name + ".img")


    def kname(name):
        return machine.succeed(f"basename $(readlink -f {BY_ID[name]})").strip()


    def audit_log():
        """The records of the VM's dfnix audit log."""
        text = machine.succeed("cat /run/dfnix/audit.jsonl")
        return [json.loads(line) for line in text.splitlines()]


    def last_dfdisk_record():
        return [r for r in audit_log() if r["tool"] == "dfdisk"][-1]


    def dfdisk(args, code, wrap=""):
        """Run `dfdisk ARGS --json` (behind the command prefix wrap), require the
        exit code and return the JSON document dfdisk printed on stdout."""
        status, out = machine.execute(f"{wrap} dfdisk {args} --json 2>/tmp/dfdisk.err")
        print(machine.succeed("cat /tmp/dfdisk.err"))
        assert status == code, f"dfdisk {args}: exit code {status}, expected {code}: {out}"
        return json.loads(out)


    def info_path(report):
        """The text report <base>.info (its JSON twin adds .json)."""
        return f"{report['output_dir']}/{report['base_name']}.info"


    def verdict(report):
        """The VERDICT line of the text report, and the whole text."""
        text = machine.succeed(f"cat {info_path(report)}")
        line = next(ln for ln in text.splitlines() if ln.startswith("VERDICT"))
        return line.split(":", 1)[1].strip(), text


    def check_audit(report):
        """The run is in the audit log ("acquisition_started", whose hash is the
        report's anchor, and one "acquisition_finished" with the report's verdict
        and digest) and in the per-boot copy of the log in the case directory.
        Returns the "started" record."""
        anchor = report["audit"]["anchor"]
        assert report["audit"]["status"] == {"state": "written"}, report["audit"]
        log = audit_log()
        started = [r for r in log if r["hash"] == anchor]
        assert len(started) == 1 and started[0]["action"] == "acquisition_started", started
        assert started[0]["details"]["base_name"] == report["base_name"], started[0]
        finished = [
            r for r in log
            if r["action"] == "acquisition_finished" and r["details"].get("anchor") == anchor
        ]
        assert len(finished) == 1 and finished[0]["outcome"] == "ok", finished
        details = finished[0]["details"]
        assert details["outcome"] == report["outcome"], details
        assert details["exit_code"] == report["exit_code"], details
        report_sha = machine.succeed(f"sha256sum {info_path(report)}.json").split()[0]
        assert details["report_json_sha256"] == report_sha, details
        # dfcore's per-boot export, refreshed after the "finished" record
        export = report["audit"]["export_file"]
        assert export == f"{report['output_dir']}/audit-{BOOT_ID}.jsonl", export
        machine.succeed(f"dfcore-audit verify {export}")
        copy = {json.loads(line)["hash"] for line in machine.succeed(f"cat {export}").splitlines()}
        assert finished[0]["hash"] in copy, f"{export} lacks the finished record"
        return started[0]


    def acquire(source, outdir, evidence, extra="", code=0, wrap=""):
        """`dfdisk acquire` with the CFTT case fields. A run that wrote a report
        returns the report (<base>.info.json, which --json printed); any other
        run returns its error, and a refusal must be in the audit log."""
        doc = dfdisk(
            f"acquire {source} -o {outdir} -C CFTT -E {evidence} -e {EXAMINER} {extra}",
            code,
            wrap,
        )
        if "error" in doc:
            err = doc["error"]
            assert err["exit_code"] == code, err
            if err["kind"] == "refused":
                last = last_dfdisk_record()
                assert last["action"] == "acquisition_refused", last
                assert last["outcome"] == "refused", last
                assert last["message"] == err["message"], last
            return err
        report = json.loads(machine.succeed(f"cat {info_path(doc)}.json"))
        assert report == doc, "--json did not print the .info.json report"
        assert report["exit_code"] == code, report["outcome_reason"]
        check_audit(report)
        return report


    def check_verified(report, sha):
        """A complete acquisition, verified, of a source whose SHA-256 is sha."""
        assert report["outcome"] == "verified", report["outcome_reason"]
        assert report["exit_code"] == 0, report["exit_code"]
        assert report["verification"]["result"]["status"] == "matched", report["verification"]
        assert report["read_errors"]["ranges"] == [], report["read_errors"]
        assert report["bytes_acquired"] == report["expected_bytes"], report["bytes_acquired"]
        assert report["acquisition_hashes"]["sha256"] == sha, report["acquisition_hashes"]
        assert report["image_hashes"]["sha256"] == sha, report["image_hashes"]
        line, _ = verdict(report)
        assert line == "VERIFIED (exit code 0)", line


    with subtest("create blank disk files"):
        FIXTURES.mkdir(parents=True, exist_ok=True)
        for d in DISKS:
            with open(image(d["name"]), "wb") as f:
                f.truncate(d["size"] << 20)

    with subtest("build dirty evidence fixtures"):
        builder.start()
        builder.wait_for_unit("multi-user.target")
        builder.succeed("make-cftt-fixtures >&2")
        builder.shutdown()

    before = {d["name"]: sha256(image(d["name"])) for d in DISKS}

    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("udevadm settle")
    BOOT_ID = machine.succeed("cat /proc/sys/kernel/random/boot_id").strip()

    with subtest("the release revision is stamped"):
        machine.succeed("grep -qx 'DFNIX_REVISION=cftt' /etc/dfnix-release")

    with subtest("the boot-time registry protects the system disk and no evidence"):
        machine.wait_for_unit("dfnix-protected-devices.service")
        registry = json.loads(machine.succeed("cat /run/dfnix/protected.json"))
        serials = [d["identity"].get("serial") for d in registry["devices"]]
        assert serials == ["SYS-ISO"], registry
        assert registry["devices"][0]["role"] == "system_disk", registry

    with subtest("hibernation resume is disabled on the kernel command line"):
        machine.succeed("grep -qw noresume /proc/cmdline")
        machine.succeed("grep -qw nohibernate /proc/cmdline")

    with subtest("every evidence disk and partition is read-only in the kernel"):
        for d in DISKS:
            dev = BY_ID[d["name"]]
            machine.succeed(f"test $(blockdev --getro {dev}) = 1")
        machine.succeed(
            "for p in /sys/class/block/vd*; do test $(cat $p/ro) = 1 || { echo $p; exit 1; }; done"
        )

    with subtest("LVM accepts the dfnix lockdown configuration"):
        # An unknown setting is only a warning, so a misplaced option is silently ignored
        out = machine.succeed("lvmconfig --validate 2>&1")
        assert "unknown" not in out.lower(), out

    with subtest("no RAID assembly, LVM activation, swap or resume"):
        machine.fail("grep -q '^md' /proc/mdstat")
        machine.fail("test -e /dev/evvg")
        machine.succeed("test -z \"$(swapon --noheadings --show)\"")
        machine.succeed("test \"$(cat /sys/power/resume)\" = 0:0")

    with subtest("polkit denies udisks mount and unlock to the wheel examiner"):
        for action in ["filesystem-mount", "encrypted-unlock"]:
            # 1 = not authorized; 2 would mean an admin challenge is offered
            machine.succeed(
                "runuser -u nixos -- sh -c "
                f"'pkcheck --action-id org.freedesktop.udisks2.{action} --process $$; test $? -eq 1'"
            )

    with subtest("dfmount mounts dirty filesystems read-only without replay"):
        for name, part, fstype, opt in [
            # the kernel reports ext4's noload as norecovery
            ("ext4", "", "ext4", "norecovery"),
            ("xfs", "", "xfs", "norecovery"),
            ("ntfs", "", "ntfs3", "ro"),
            ("hiber", "-part2", "ext4", "norecovery"),
        ]:
            dev = BY_ID[name] + part
            kn = machine.succeed(f"basename $(readlink -f {dev})").strip()
            out = machine.succeed(f"dfmount evidence {dev}")
            assert fstype in out, out
            mnt = f"/media/evidence/{kn}"
            opts = machine.succeed(f"findmnt -no OPTIONS {mnt}").strip().split(",")
            assert "ro" in opts and opt in opts, opts
            machine.succeed(f"grep -q 'dfnix CFTT {name} evidence' {mnt}/evidence.txt")
            if name in ("ext4", "xfs"):
                # Present only in the unreplayed journal/log (replay proven by the builder)
                machine.fail(f"test -e {mnt}/journal-only.txt")
            machine.succeed(f"dfmount umount {mnt}")

    with subtest("dfmount refuses containers and raw members"):
        for name, part, reason in [
            ("luks", "", "--readonly"),
            ("raid-a", "", "raid"),
            ("lvm", "", "raid"),
            ("hiber", "-part1", "not a mountable filesystem"),
        ]:
            out = machine.fail(f"dfmount evidence {BY_ID[name]}{part} 2>&1")
            assert reason in out, out

    with subtest("LUKS opened read-only can be examined"):
        machine.succeed(f"printf evidence | cryptsetup open --readonly --key-file - {BY_ID['luks']} evluks")
        out = machine.succeed("dfmount evidence /dev/mapper/evluks")
        mnt = machine.succeed("findmnt -no TARGET -S /dev/mapper/evluks").strip()
        machine.succeed(f"grep -q 'dfnix CFTT luks evidence' {mnt}/evidence.txt")
        machine.succeed(f"dfmount umount {mnt}")
        machine.succeed("cryptsetup close evluks")

    target = kname("target")
    dest = f"/media/target/{target}"

    with subtest("dfmount prepares the target disk only after typed confirmation"):
        machine.fail(f"dfmount unblock {BY_ID['target']} --confirm wrong")
        machine.succeed(f"test $(blockdev --getro {BY_ID['target']}) = 1")
        machine.succeed(f"dfmount unblock {BY_ID['target']} --confirm {target}")
        machine.succeed(f"mkfs.ext4 -q -L CFTT-TARGET {BY_ID['target']}")
        machine.succeed(f"dfmount target {BY_ID['target']} --confirm {target}")
        machine.succeed(f"findmnt -no OPTIONS {dest} | grep -q rw")

    with subtest("dfdisk RAW and E01 acquisitions are verified and match the fixture hashes"):
        # --examiner is required: a usage error (exit 2) before anything is touched
        status, out = machine.execute(
            f"dfdisk acquire {BY_ID['xfs']} --format raw -o {dest}/case -C CFTT -E XFS01 2>&1"
        )
        assert status == 2 and "--examiner" in out, out
        machine.succeed(f"test ! -e {dest}/case")

        xfs01 = acquire(BY_ID["xfs"], f"{dest}/case", "XFS01", "--format raw")
        check_verified(xfs01, before["xfs"])
        raw_hash = machine.succeed(f"sha256sum {xfs01['image_files'][0]} | cut -d' ' -f1").strip()
        assert raw_hash == before["xfs"], (raw_hash, before["xfs"])
        # The dfnix udev rule made the disk read-only; dfdisk records that and its claim
        wp = xfs01["write_protection"]
        assert wp["sysfs_ro_before"] is True and wp["set_by_dfdisk"] is False, wp
        assert wp["exclusive_open"] is True and wp["dfnix_registry"] == {"state": "present"}, wp
        assert xfs01["provenance"]["dfnix_revision"] == "cftt", xfs01["provenance"]

        ext401 = acquire(BY_ID["ext4"], f"{dest}/case", "EXT401", "--format e01")
        check_verified(ext401, before["ext4"])
        assert ext401["image_files"][0].endswith(".E01"), ext401["image_files"]

    with subtest("dfdisk refuses to overwrite an existing acquisition"):
        outputs = f"{info_path(ext401)} {info_path(ext401)}.json {ext401['image_files'][0]}"
        kept = machine.succeed(f"sha256sum {outputs}")
        err = acquire(BY_ID["ext4"], f"{dest}/case", "EXT401", "--format e01", code=3)
        assert "Refusing to overwrite" in err["message"], err
        assert machine.succeed(f"sha256sum {outputs}") == kept

    with subtest("dfdisk refuses a destination stored on the source disk"):
        tl = kname("target-lvm")
        machine.succeed(f"dfmount unblock {BY_ID['target-lvm']} --confirm {tl}")
        machine.succeed(
            f"pvcreate -q {BY_ID['target-lvm']} && vgcreate -q tvg {BY_ID['target-lvm']}"
            " && lvcreate -q -y -l 100%FREE -n tlv tvg && mkfs.ext4 -q /dev/tvg/tlv"
            " && mkdir -p /mnt/onsource && mount /dev/tvg/tlv /mnt/onsource"
        )
        # The destination lives on an LV of the source disk, which is therefore
        # mounted: the source safety check (mounts through holders) stops first
        err = acquire(BY_ID["target-lvm"], "/mnt/onsource/case", "SELF01", "--format raw", code=3)
        assert "is mounted" in err["message"] and "/mnt/onsource" in err["message"], err
        machine.succeed("test -z \"$(ls -A /mnt/onsource/case 2>/dev/null)\"")
        machine.succeed("umount /mnt/onsource && vgchange -q -an tvg")

        # A loop device backed by a file on the target disk: no mount on the source
        # is visible, so only the destination check (loop backing file -> disk) can stop it
        machine.succeed(f"dd if=/dev/zero of={dest}/backing.img bs=1M count=8 status=none")
        loop = machine.succeed(f"losetup -f --show {dest}/backing.img").strip()
        err = acquire(loop, f"{dest}/loopcase", "LOOP01", "--format raw", code=3)
        assert "Critical Safety Error" in err["message"], err
        assert f"shares physical disk {target}" in err["message"], err
        machine.succeed(f"test -z \"$(ls -A {dest}/loopcase 2>/dev/null)\"")
        machine.succeed(f"losetup -d {loop}")

    with subtest("dfnet receives and verifies a stream bound to one address"):
        size = machine.succeed(f"blockdev --getsize64 {BY_ID['ext4']}").strip()
        machine.fail(
            f"dfnet receive 9999 {dest}/net.raw --bind 0.0.0.0 --expected-bytes {size}"
            f" --expected-sha256 {before['ext4']}"
        )
        machine.succeed(
            f"dfnet receive 9999 {dest}/net.raw --bind 127.0.0.1 --expected-bytes {size}"
            f" --expected-sha256 {before['ext4']} >/tmp/receive.log 2>&1 &"
        )
        # Probing the port would itself be the receiver's single accepted connection
        machine.wait_until_succeeds("grep -q 'Listening on 127.0.0.1:9999' /tmp/receive.log")
        machine.succeed(f"cat {BY_ID['ext4']} > /dev/tcp/127.0.0.1/9999")
        machine.wait_until_succeeds(f"grep -q '\"status\": \"verified\"' {dest}/net.raw.json")

    with subtest("the registry protects the system disk, mounted or not"):
        sysdisk = kname("system")
        # dfdisk does not acquire it while it is mounted
        err = acquire(BY_ID["system"], f"{dest}/sys", "SYS01", "--format raw", code=3)
        assert "protected by the dfnix registry" in err["message"], err
        # ... nor after it was unmounted
        machine.succeed("umount /iso")
        out = machine.fail(f"dfmount unblock {BY_ID['system']} --confirm {sysdisk} 2>&1")
        assert "protected by the dfnix registry" in out, out
        err = acquire(BY_ID["system"], f"{dest}/sys", "SYS01", "--format raw", code=3)
        assert "protected by the dfnix registry" in err["message"], err
        machine.succeed(f"test ! -e {dest}/sys")
        machine.succeed(f"test $(blockdev --getro {BY_ID['system']}) = 1")

    with subtest("dfinfo triage runs"):
        machine.succeed("dfinfo -p > /tmp/dfinfo.txt")
        machine.succeed("grep -q 'DFNIX FORENSIC SYSTEM TRIAGE REPORT' /tmp/dfinfo.txt")

    with subtest("the audit chain verifies and records every tool action"):
        machine.succeed("dfcore-audit verify")
        records = audit_log()
        assert records[0]["action"] == "protected_registry", records[0]
        assert all(r["system_revision"] == "cftt" for r in records)
        seen = {(r["tool"], r["action"], r["outcome"]) for r in records}
        for expected in [
            ("dfmount", "evidence_mount", "ok"),
            ("dfmount", "evidence_mount", "refused"),
            ("dfmount", "unblock_refused", "refused"),
            ("dfmount", "unblock", "ok"),
            ("dfmount", "target_mount", "ok"),
            ("dfdisk", "acquisition_started", "ok"),
            ("dfdisk", "acquisition_finished", "ok"),
            ("dfdisk", "acquisition_refused", "refused"),
            ("dfnet", "receive_started", "ok"),
            ("dfnet", "receive_finished", "ok"),
        ]:
            assert expected in seen, (expected, sorted(seen))
        # Every acquisition that started ended with a report; their verdicts
        finished = [r for r in records if r["action"] == "acquisition_finished"]
        started = [r for r in records if r["action"] == "acquisition_started"]
        assert len(finished) == len(started), (len(finished), len(started))
        assert all(r["outcome"] == "ok" for r in finished), finished
        verdicts = {r["details"]["outcome"] for r in finished}
        assert verdicts == {"verified"}, verdicts

    with subtest("reports, manifests and the case copy are anchored in the chain"):
        hashes = {r["hash"] for r in records}
        assert xfs01["audit"]["anchor"] in hashes, xfs01["audit"]
        manifest = json.loads(machine.succeed(f"cat {dest}/net.raw.json"))
        assert manifest["audit_anchor"] in hashes, manifest
        # dfcore's per-boot export with its head, in the case directory
        export = ext401["audit"]["export_file"]
        assert export == f"{dest}/case/audit-{BOOT_ID}.jsonl", export
        machine.succeed(f"dfcore-audit verify {export}")
        head = machine.succeed(f"cat {dest}/case/audit-{BOOT_ID}.head").split()[0]
        assert head == machine.succeed(f"dfcore-audit head {export}").strip(), head
        assert head in hashes, head

    with subtest("tampering with the audit log is detected"):
        machine.succeed("cp /run/dfnix/audit.jsonl /tmp/tampered.jsonl")
        machine.succeed("sed -i '2s/\"outcome\":\"ok\"/\"outcome\":\"error\"/' /tmp/tampered.jsonl")
        machine.fail("cmp -s /run/dfnix/audit.jsonl /tmp/tampered.jsonl")
        out = machine.fail("dfcore-audit verify /tmp/tampered.jsonl 2>&1")
        assert "line 2" in out, out

    machine.succeed(f"sync && umount {dest}")
    machine.shutdown()

    with subtest("evidence images are bit-identical after the session"):
        changed = [d["name"] for d in EVIDENCE if sha256(image(d["name"])) != before[d["name"]]]
        assert not changed, f"evidence modified: {changed}"

    with subtest("negative control: writes to the unblocked target reach the image files"):
        assert sha256(image("target")) != before["target"]
  '';
}
