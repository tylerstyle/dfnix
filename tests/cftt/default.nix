# CFTT-style write-blocking regression test (Phase 1a, module level).
#
# A builder VM creates dirty evidence disks (unreplayed ext4 journal, dirty XFS
# log, dirty NTFS, LUKS, RAID1 members, LVM, hibernation image, a ZFS pool left
# imported) and a pattern disk whose sectors name themselves. The host hashes
# the raw disk files, boots a VM with the dfnix write-blocking module and the
# forensic tools on the same files, exercises dfmount / dfdisk / dfnet / dfinfo
# and the read-only md, LVM and ZFS reassembly, shuts it down and requires every
# evidence file to be bit-identical.
#
# dfdisk (0.2.0) is held to its exit codes, its .info.json reports and its audit
# records: verified acquisitions, refusals (overwrite, identity, in use, tmpfs,
# mounted, destination on the source, protected disk), read errors injected
# with device-mapper `error` targets (RAW stop and zero-fill, E01, rescue), the
# exclusive claim the external tools read under (R1), write protection,
# `dfdisk unmount` and `dfdisk verify`.
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
    # Every sector names itself: read errors and exclusive claims are mapped
    # over it with device-mapper
    { name = "pattern"; serial = "EVID-PATTERN"; size = 32; evidence = true; }
    # A ZFS pool that was never exported (ZFS needs at least 64 MiB per device)
    { name = "zfs"; serial = "EVID-ZFS"; size = 128; evidence = true; }
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
    boot.supportedFilesystems = [ "ntfs" "xfs" "zfs" ];
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

  # Exclusive (O_EXCL) claims of block devices, as a mount or a dm table takes them
  exclTool = pkgs.writeScriptBin "cftt-excl" (
    "#!${pkgs.python3.interpreter}\n" + builtins.readFile ./excl.py
  );

  diskList = builtins.toJSON (map (d: { inherit (d) name serial size evidence; }) disks);
in
pkgs.testers.runNixOSTest {
  name = "dfnix-cftt";

  nodes.builder = {
    imports = [ vmBase ];
    environment.systemPackages = [ makeFixtures ];
    virtualisation.memorySize = 2048;
    # Another host than dfnix (64666e78): the pool it leaves imported is foreign
    networking.hostId = "c0ffee00";
    boot.zfs.forceImportRoot = false;
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
      mdadm
      polkit
      exclTool
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
    import re

    DISKS = json.loads(${builtins.toJSON diskList})
    EVIDENCE = [d for d in DISKS if d["evidence"]]
    BY_ID = {d["name"]: "/dev/disk/by-id/virtio-" + d["serial"] for d in DISKS}
    FIXTURES = builder.shared_dir / "cftt"
    SECTOR = 512
    EXAMINER = "cftt-examiner"
    # Unreadable areas mapped over the pattern disk, as (first sector, sectors):
    # three sectors inside one 4 KiB page, and 256 KiB starting on a 1 MiB boundary
    BAD = [(10243, 3), (40960, 512)]
    BAD_BYTES = [(first * SECTOR, count * SECTOR) for first, count in BAD]
    # Status column of the read-error table in the text report
    RANGE_LABEL = {"substituted": "unreadable, zero-filled", "unread": "not read"}


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


    def digest(data, zeroed=(), algorithm="sha256"):
        """Digest of data with the (offset, length) ranges in zeroed replaced by zeros."""
        buf = bytearray(data)
        for offset, length in zeroed:
            buf[offset:offset + length] = bytes(length)
        return hashlib.new(algorithm, buf).hexdigest()


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


    def table(report):
        """The read-error table of a report as (offset, length, kind)."""
        return [(r["offset"], r["length"], r["kind"]) for r in report["read_errors"]["ranges"]]


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
        assert len(finished) == 1, finished
        # The record's own outcome is "ok" only for a verdict that is not a
        # failure (exit code 0, 7 or 9); otherwise "error" with the verdict
        want = "ok" if report["exit_code"] in (0, 7, 9) else "error"
        assert finished[0]["outcome"] == want, finished
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


    def check_text(report, label):
        """The text report states the verdict label and lists every range of the
        read-error table; nothing in it claims that all hashes match."""
        line, text = verdict(report)
        assert line == f"{label} (exit code {report['exit_code']})", line
        assert "ALL HASHES MATCH" not in text
        for offset, length, kind in table(report):
            row = rf"^\s+\d+\s+{offset}\s+{length}\s+\d+\s+{RANGE_LABEL[kind]}$"
            assert re.search(row, text, re.M), f"no read-error row {offset}+{length} {kind}"


    def dm_create(name, lines):
        """A read-only device-mapper device (the disks below are read-only)."""
        quoted = " ".join(f"'{ln}'" for ln in lines)
        machine.succeed(f"printf '%s\\n' {quoted} | dmsetup create --readonly {name}")
        machine.succeed("udevadm settle")
        return f"/dev/mapper/{name}"


    def error_table(dev, sectors, bad):
        """dm table of dev, linear except for an error target over each
        (first sector, sectors) in bad."""
        lines = []
        pos = 0
        for first, count in bad:
            if first > pos:
                lines.append(f"{pos} {first - pos} linear {dev} {pos}")
            lines.append(f"{first} {count} error")
            pos = first + count
        if pos < sectors:
            lines.append(f"{pos} {sectors - pos} linear {dev} {pos}")
        return lines


    def map_blocks(text):
        """(offset, length, status) of every block of a GNU ddrescue map."""
        rows = [ln.split() for ln in text.splitlines() if ln.strip() and not ln.startswith("#")]
        # rows[0] is the status line: current position, phase, pass
        return [(int(pos, 16), int(size, 16), status) for pos, size, status in rows[1:]]


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
    pattern = image("pattern").read_bytes()
    PATTERN_SIZE = len(pattern)
    PATTERN_SECTORS = PATTERN_SIZE // SECTOR
    assert pattern[40960 * SECTOR:][:37] == b"dfnix CFTT pattern sector 0000040960\n"

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

    with subtest("no RAID assembly, LVM activation, ZFS import, swap or resume"):
        machine.fail("grep -q '^md' /proc/mdstat")
        machine.fail("test -e /dev/evvg")
        # Loading the module imports nothing: there is no zpool.cache
        machine.succeed("test ! -e /etc/zfs/zpool.cache")
        machine.succeed("modprobe zfs")
        out = machine.succeed("zpool list -H -o name 2>&1")
        assert "evpool" not in out, out
        machine.succeed("test -z \"$(swapon --noheadings --show)\"")
        machine.succeed("test \"$(cat /sys/power/resume)\" = 0:0")

    with subtest("ZFS never mounts, shares, trims, scrubs or syncs a pool on its own"):
        for unit in ["zfs-mount", "zfs-share", "zfs-zed"]:
            machine.succeed(f"test \"$(systemctl is-enabled {unit}.service)\" = masked")
        for unit in ["zpool-trim.timer", "zfs-scrub.timer"]:
            machine.fail(f"systemctl cat {unit}")
        # The shutdown ramfs is built at shutdown; build it now to read the hook
        machine.succeed("systemctl start generate-shutdown-ramfs.service")
        hook = "/run/initramfs/etc/systemd/system-shutdown/zpool"
        machine.succeed(f"grep -qx 'exit 0' {hook}")
        machine.fail(f"grep -q 'zpool' {hook}")

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

    with subtest("md, LVM and ZFS reassemble read-only from read-only loop devices"):
        # The documented procedure: image every member with dfdisk, attach the
        # images with `losetup -r` and assemble those. The evidence disks stand
        # in for the member images.
        def ro_loop(name, partscan=False):
            scan = "-P " if partscan else ""
            loop = machine.succeed(f"losetup -r {scan}-f --show {BY_ID[name]}").strip()
            machine.succeed(f"test $(blockdev --getro {loop}) = 1")
            return loop

        machine.succeed("mkdir -p /mnt/md /mnt/lvm")

        raid = [ro_loop("raid-a"), ro_loop("raid-b")]
        # A plain node: /dev/md/<name> links come from mdadm's udev rules, which
        # dfnix leaves out
        machine.succeed(f"mdadm --assemble --readonly /dev/md100 {' '.join(raid)}")
        machine.succeed("test $(cat /sys/block/md100/md/array_state) = readonly")
        machine.succeed("mount -o ro,noload /dev/md100 /mnt/md")
        machine.succeed("grep -q 'dfnix CFTT raid evidence' /mnt/md/evidence.txt")
        machine.succeed("umount /mnt/md && mdadm --stop /dev/md100")

        # --devices keeps LVM off the evidence disk that carries the same PV
        lvm = ro_loop("lvm")
        lvm_ro = (
            f"--devices {lvm} --config "
            "'global { metadata_read_only = 1 } activation { read_only_volume_list = [ \"evvg\" ] }'"
        )
        machine.succeed(f"vgchange -ay {lvm_ro} evvg")
        machine.succeed("test $(blockdev --getro /dev/evvg/evlv) = 1")
        machine.succeed("mount -o ro,noload /dev/evvg/evlv /mnt/lvm")
        machine.succeed("grep -q 'dfnix CFTT lvm evidence' /mnt/lvm/evidence.txt")
        machine.succeed(f"umount /mnt/lvm && vgchange -an {lvm_ro} evvg")

        # The pool was never exported, so ZFS asks for -f: safe with readonly=on
        zfs = ro_loop("zfs", partscan=True)
        zimport = f"zpool import -o readonly=on -o cachefile=none -N -R /mnt/zfs -d {zfs}p1"
        out = machine.fail(f"{zimport} evpool 2>&1")
        assert "another system" in out, out
        machine.succeed(f"{zimport} -f evpool")
        machine.succeed("test $(zpool get -H -o value readonly evpool) = on")
        machine.succeed("zfs mount evpool")
        machine.succeed("grep -q 'dfnix CFTT zfs evidence' /mnt/zfs/evpool/evidence.txt")
        machine.succeed("zpool export evpool")
        machine.succeed("test ! -e /etc/zfs/zpool.cache")

        machine.succeed(f"losetup -d {' '.join(raid + [lvm, zfs])}")

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

    with subtest("dfdisk refuses a source that is not the expected device"):
        err = acquire(
            BY_ID["ext4"], f"{dest}/expect", "EXP01", "--format raw --expect-serial EVID-WRONG", code=3
        )
        assert "expected serial EVID-WRONG" in err["message"] and "EVID-EXT4" in err["message"], err
        machine.succeed(f"test ! -e {dest}/expect")
        # The dry run with the right expectations is ready, and writes nothing either
        ext4_bytes = machine.succeed(f"blockdev --getsize64 {BY_ID['ext4']}").strip()
        ready = dfdisk(
            f"check {BY_ID['ext4']} -o {dest}/expect -C CFTT -E EXP01 -e {EXAMINER} --format raw"
            f" --expect-serial EVID-EXT4 --expect-size {ext4_bytes}",
            0,
        )
        assert ready["ready"] is True, ready["problems"]
        machine.succeed(f"test ! -e {dest}/expect")

    with subtest("dfdisk refuses a source another process holds exclusively"):
        # An O_EXCL claim, as md, dm or another imager would hold it
        machine.succeed(
            f"cftt-excl hold {BY_ID['pattern']} /tmp/held >/dev/null 2>&1 & echo $! >/tmp/held.pid"
        )
        machine.wait_for_file("/tmp/held")
        err = acquire(BY_ID["pattern"], f"{dest}/inuse", "INUSE01", "--format raw", code=3)
        assert "in use" in err["message"], err
        busy = dfdisk(
            f"check {BY_ID['pattern']} -o {dest}/inuse -C CFTT -E INUSE01 -e {EXAMINER} --format raw", 3
        )
        assert any("in use" in p["message"] for p in busy["problems"]), busy["problems"]
        machine.succeed("kill $(cat /tmp/held.pid)")
        machine.wait_until_succeeds(f"cftt-excl probe {BY_ID['pattern']}")

        # A filesystem mounted in another mount namespace: not in dfdisk's mount
        # table, so only the exclusive open can find it
        machine.succeed("mkdir -p /mnt/ns")
        machine.succeed(
            "unshare --mount sh -c "
            f"'mount -o ro,noload {BY_ID['ext4']} /mnt/ns && touch /tmp/ns-mounted && exec sleep infinity'"
            " >/dev/null 2>&1 & echo $! >/tmp/ns.pid"
        )
        machine.wait_for_file("/tmp/ns-mounted")
        machine.fail("mountpoint -q /mnt/ns")
        err = acquire(BY_ID["ext4"], f"{dest}/inuse", "INUSE02", "--format raw", code=3)
        assert "in use" in err["message"], err
        machine.succeed("kill $(cat /tmp/ns.pid)")
        machine.wait_until_succeeds(f"cftt-excl probe {BY_ID['ext4']}")
        machine.succeed(f"test ! -e {dest}/inuse")

    with subtest("dfdisk refuses a tmpfs destination unless --allow-tmpfs"):
        machine.succeed("mkdir -p /mnt/ram && mount -t tmpfs -o size=160m cftt-ram /mnt/ram")
        err = acquire(BY_ID["pattern"], "/mnt/ram/case", "RAM01", "--format raw", code=3)
        assert "tmpfs" in err["message"] and "--allow-tmpfs" in err["message"], err
        machine.succeed("test ! -e /mnt/ram/case")
        ram = acquire(BY_ID["pattern"], "/mnt/ram/case", "RAM01", "--format raw --allow-tmpfs")
        check_verified(ram, before["pattern"])
        assert any("allowed by --allow-tmpfs" in n for n in ram["notes"]), ram["notes"]
        machine.succeed("umount /mnt/ram")

    with subtest("dfdisk reports read errors exactly (device-mapper error targets)"):
        pattern_dev = "/dev/" + kname("pattern")
        everr = dm_create("everr", error_table(pattern_dev, PATTERN_SECTORS, BAD))
        out_dir = f"{dest}/readerr"
        zeroed = digest(pattern, BAD_BYTES)

        # RAW, --on-read-error stop: INCOMPLETE, ending at the first unreadable sector
        first = BAD_BYTES[0][0]
        stop = acquire(everr, out_dir, "RAWSTOP", "--format raw --on-read-error stop", code=6)
        assert stop["outcome"] == "incomplete", stop["outcome_reason"]
        assert stop["bytes_acquired"] == first, stop["bytes_acquired"]
        assert table(stop) == [(first, PATTERN_SIZE - first, "unread")], table(stop)
        assert f"read error at byte offset {first} (sector {BAD[0][0]})" in stop["stop_reason"], stop
        assert stop["acquisition_hashes"]["sha256"] == digest(pattern[:first]), stop["acquisition_hashes"]
        machine.succeed(f"test $(stat -c %s {stop['image_files'][0]}) = {first}")
        check_text(stop, "INCOMPLETE")

        # RAW, --on-read-error zero-fill: each unreadable sector, exactly, as zeros
        zero = acquire(everr, out_dir, "RAWZERO", "--format raw --on-read-error zero-fill", code=7)
        assert zero["outcome"] == "completed_with_read_errors", zero["outcome_reason"]
        assert table(zero) == [(o, n, "substituted") for o, n in BAD_BYTES], table(zero)
        assert zero["bytes_acquired"] == PATTERN_SIZE, zero["bytes_acquired"]
        assert zero["acquisition_hashes"]["sha256"] == zeroed, zero["acquisition_hashes"]
        assert zero["image_hashes"]["sha256"] == zeroed, zero["image_hashes"]
        check_text(zero, "COMPLETED WITH READ ERRORS")

        # E01: ewfacquire lists what it zero-filled in its error granularity, which
        # can include readable sectors next to an unreadable one (the E01 engine's
        # documented behaviour; buffered reads fail by whole page-cache blocks). The
        # table must hold every injected sector, nothing outside the 1 MiB blocks
        # around them, and be exactly the sectors that are zeros in the image.
        e01 = acquire(everr, out_dir, "E01ERR", "--format e01", code=7)
        assert e01["outcome"] == "completed_with_read_errors", e01["outcome_reason"]
        listed = table(e01)
        assert listed and all(kind == "substituted" for _, _, kind in listed), listed
        injected = {s for o, n in BAD_BYTES for s in range(o // SECTOR, (o + n) // SECTOR)}
        reported = {s for o, n, _ in listed for s in range(o // SECTOR, (o + n + SECTOR - 1) // SECTOR)}
        assert injected <= reported, f"unreadable sectors missing from the E01 report: {listed}"
        near = {s // 2048 for s in injected}
        assert all(s // 2048 in near for s in reported), f"errors reported far from any bad sector: {listed}"
        for algorithm in ("md5", "sha256"):
            expected_digest = digest(pattern, [(o, n) for o, n, _ in listed], algorithm)
            assert e01["acquisition_hashes"][algorithm] == expected_digest, (algorithm, listed)
        assert e01["verification"]["result"]["status"] == "matched", e01["verification"]
        check_text(e01, "COMPLETED WITH READ ERRORS")

        # Rescue: dfdisk runs GNU ddrescue with direct I/O and without -n/-N, so
        # ddrescue trims and scrapes every failed area down to single sectors and
        # its map ends with finished (+) and bad-sector (-) blocks only: complete
        # with read errors (7), not incomplete (6, which untried, non-trimmed or
        # non-scraped areas would mean)
        rescue = acquire(everr, out_dir, "RESCUEERR", "--rescue", code=7)
        assert rescue["outcome"] == "completed_with_read_errors", rescue["outcome_reason"]
        assert rescue["read_errors"]["source"] == "ddrescue mapfile", rescue["read_errors"]
        assert table(rescue) == [(o, n, "substituted") for o, n in BAD_BYTES], table(rescue)
        map_file = next(f for f in rescue["auxiliary_files"] if f["path"].endswith(".map"))
        assert machine.succeed(f"sha256sum {map_file['path']}").split()[0] == map_file["sha256"]
        blocks = map_blocks(machine.succeed(f"cat {map_file['path']}"))
        assert [(o, n) for o, n, s in blocks if s == "-"] == BAD_BYTES, blocks
        assert {s for _, _, s in blocks} == {"+", "-"}, blocks
        assert rescue["image_hashes"]["sha256"] == zeroed, rescue["image_hashes"]
        check_text(rescue, "COMPLETED WITH READ ERRORS")

        machine.succeed("dmsetup remove --retry everr")

    with subtest("R1: ewfacquire and ddrescue read the source while dfdisk holds its claim"):
        # dm-delay (linear, 50 ms per request) keeps each tool reading long enough
        # to try an exclusive claim of the source while it reads
        r1_bytes = 16 << 20
        machine.succeed("modprobe dm-delay")
        r1slow = dm_create("r1slow", [f"0 {r1_bytes // SECTOR} delay {pattern_dev} 0 50"])
        for evidence, extra, tool, code in [
            ("R1E01", "--format e01", "ewfacquire", 0),
            ("R1RESCUE", "--rescue", "ddrescue", 9),
            ("R1RESCUEV", "--rescue --verify-source", "ddrescue", 0),
        ]:
            r1 = acquire(
                r1slow, f"{dest}/r1", evidence, extra, code, f"cftt-excl during {tool} {r1slow} /tmp/r1.log"
            )
            probe_log = machine.succeed("cat /tmp/r1.log")
            print(probe_log)
            assert "reading:" in probe_log and "busy:" in probe_log, probe_log
            assert "still reading: []" not in probe_log, probe_log
            assert r1["read_errors"]["ranges"] == [], r1["read_errors"]
            assert r1["write_protection"]["exclusive_open"] is True, r1["write_protection"]
            source_hashes = r1["acquisition_hashes"] if tool == "ewfacquire" else r1["image_hashes"]
            assert source_hashes["sha256"] == digest(pattern[:r1_bytes]), source_hashes
            if "--verify-source" in extra:
                assert r1["verification"]["source_reread"]["status"] == "matched", r1["verification"]
            # The tool opened the source itself, by the path the "started" record names
            tool_path = check_audit(r1)["details"]["tool_source_path"]
            assert any(
                c["argv"][0].split("/")[-1] == tool and tool_path in c["argv"]
                for c in r1["provenance"]["commands"]
            ), r1["provenance"]["commands"]
            machine.succeed(f"test $(readlink -f {tool_path}) = $(readlink -f {r1slow})")
        # The claim ends with the run
        machine.succeed(f"cftt-excl probe {r1slow}")
        machine.succeed("dmsetup remove --retry r1slow")

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

    with subtest("dfdisk unmount unmounts a mounted evidence partition and records it"):
        part = BY_ID["hiber"] + "-part2"
        kn = machine.succeed(f"basename $(readlink -f {part})").strip()
        mnt = f"/media/evidence/{kn}"
        machine.succeed(f"dfmount evidence {part}")
        machine.succeed(f"mountpoint -q {mnt}")
        # dfdisk never acquires a mounted source
        err = acquire(BY_ID["hiber"], f"{dest}/mounted", "MNT01", "--format raw", code=3)
        assert "is mounted" in err["message"] and mnt in err["message"], err
        machine.succeed(f"test ! -e {dest}/mounted")
        unmounted = dfdisk(f"unmount {part}", 0)
        assert unmounted["unmounted"] == [mnt], unmounted
        machine.fail(f"mountpoint -q {mnt}")
        rec = last_dfdisk_record()
        assert rec["action"] == "unmount" and rec["outcome"] == "ok", rec
        assert rec["hash"] == unmounted["audit_record"], (rec, unmounted)
        assert rec["details"]["mounts_before"] == [mnt], rec["details"]
        assert rec["details"]["unmounted"] == [mnt], rec["details"]

    with subtest("dfdisk sets a writable source disk and its partitions read-only and says so"):
        hiber = kname("hiber")
        nodes = [f"/dev/{hiber}", f"/dev/{hiber}1", f"/dev/{hiber}2"]
        # As on a host without the dfnix udev rule
        machine.succeed(f"blockdev --setrw {' '.join(nodes)}")
        for node in nodes:
            machine.succeed(f"test $(blockdev --getro {node}) = 0")
        wp01 = acquire(BY_ID["hiber"], f"{dest}/wp", "WP01", "--format raw")
        check_verified(wp01, before["hiber"])
        wp = wp01["write_protection"]
        assert wp["sysfs_ro_before"] is False, wp
        assert sorted((n["node"], n["ro"]) for n in wp["partitions_ro_before"]) == [
            (n, False) for n in nodes[1:]
        ], wp
        assert wp["set_by_dfdisk"] is True and wp["method"] == "BLKROSET ioctl", wp
        assert sorted(wp["nodes_set"]) == nodes and wp["nodes_set"][0] == nodes[0], wp
        assert sorted((n["node"], n["ro"]) for n in wp["ro_after"]) == [(n, True) for n in nodes], wp
        _, text = verdict(wp01)
        assert "BLKROSET ioctl on " + ", ".join(wp["nodes_set"]) in text, text
        finished = [
            r for r in audit_log()
            if r["action"] == "acquisition_finished"
            and r["details"].get("anchor") == wp01["audit"]["anchor"]
        ]
        assert finished[0]["details"]["write_protection"]["nodes_set"] == wp["nodes_set"], finished
        # dfdisk leaves the read-only flag set after the acquisition
        for node in nodes:
            machine.succeed(f"test $(blockdev --getro {node}) = 1")

    with subtest("dfdisk verify re-checks an image against its report"):
        for rep in (xfs01, ext401, wp01):
            checked = dfdisk(f"verify {rep['image_files'][0]} --report {info_path(rep)}.json", 0)
            assert checked["exit_code"] == 0, checked
            rec = last_dfdisk_record()
            assert rec["action"] == "image_verification" and rec["details"]["exit_code"] == 0, rec
        # A copy with one byte changed no longer matches the report
        img = wp01["image_files"][0]
        tampered = f"{dest}/tampered/" + img.split("/")[-1]
        machine.succeed(f"mkdir -p {dest}/tampered && cp {img} {tampered}")
        machine.succeed(f"printf X | dd of={tampered} bs=1 seek=1000000 conv=notrunc status=none")
        checked = dfdisk(f"verify {tampered} --report {info_path(wp01)}.json", 5)
        assert checked["exit_code"] == 5, checked
        rec = last_dfdisk_record()
        assert rec["action"] == "image_verification" and rec["details"]["exit_code"] == 5, rec
        # Every verification leaves an addendum next to the image
        machine.succeed(f"ls {dest}/tampered/*.verify-*.txt")

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
        # dfdisk neither unmounts nor acquires it while it is mounted
        err = dfdisk(f"unmount {BY_ID['system']}", 3)["error"]
        assert "protected by the dfnix registry" in err["message"], err
        machine.succeed("mountpoint -q /iso")
        rec = last_dfdisk_record()
        assert rec["action"] == "unmount" and rec["outcome"] == "refused", rec
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
            ("dfdisk", "unmount", "ok"),
            ("dfdisk", "unmount", "refused"),
            ("dfdisk", "image_verification", "ok"),
            ("dfnet", "receive_started", "ok"),
            ("dfnet", "receive_finished", "ok"),
        ]:
            assert expected in seen, (expected, sorted(seen))
        # Every acquisition that started ended with a report; their verdicts
        finished = [r for r in records if r["action"] == "acquisition_finished"]
        started = [r for r in records if r["action"] == "acquisition_started"]
        assert len(finished) == len(started), (len(finished), len(started))
        assert all(
            r["outcome"] == ("ok" if r["details"]["exit_code"] in (0, 7, 9) else "error")
            for r in finished
        ), finished
        verdicts = {r["details"]["outcome"] for r in finished}
        assert verdicts == {
            "verified", "complete_unverified", "completed_with_read_errors", "incomplete"
        }, verdicts

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
