# CFTT-style write-blocking regression test (Phase 1a, module level).
#
# A builder VM creates dirty evidence disks (unreplayed ext4 journal, dirty XFS
# log, dirty NTFS, LUKS, RAID1 members, LVM, hibernation image). The host hashes
# the raw disk files, boots a VM with the dfnix write-blocking module and the
# forensic tools on the same files, exercises dfmount / dfdisk / dfnet / dfinfo,
# shuts it down and requires every evidence file to be bit-identical.
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
    ];
    virtualisation.memorySize = 2048;

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

    with subtest("dfdisk RAW and E01 acquisitions match the fixture hashes"):
        machine.succeed(
            f"dfdisk acquire {BY_ID['xfs']} --format raw -o {dest}/case -C CFTT -E XFS01 >&2"
        )
        raw_hash = machine.succeed(f"sha256sum {dest}/case/*xfs01*.raw | cut -d' ' -f1").strip()
        assert raw_hash == before["xfs"], (raw_hash, before["xfs"])
        machine.succeed(f"grep -q 'VERIFIED - ALL HASHES MATCH' {dest}/case/*xfs01*.info")

        machine.succeed(
            f"dfdisk acquire {BY_ID['ext4']} --format e01 -o {dest}/case -C CFTT -E EXT401 >&2"
        )
        info = machine.succeed(f"cat {dest}/case/*ext401*.info")
        assert "VERIFIED - ALL HASHES MATCH" in info, info
        assert before["ext4"] in info, info

    with subtest("dfdisk refuses to overwrite an existing acquisition"):
        out = machine.fail(
            f"dfdisk acquire {BY_ID['ext4']} --format e01 -o {dest}/case -C CFTT -E EXT401 2>&1"
        )
        assert "already exists" in out, out

    with subtest("dfdisk refuses a destination stored on the source disk"):
        tl = kname("target-lvm")
        machine.succeed(f"dfmount unblock {BY_ID['target-lvm']} --confirm {tl}")
        machine.succeed(
            f"pvcreate -q {BY_ID['target-lvm']} && vgcreate -q tvg {BY_ID['target-lvm']}"
            " && lvcreate -q -y -l 100%FREE -n tlv tvg && mkfs.ext4 -q /dev/tvg/tlv"
            " && mkdir -p /mnt/onsource && mount /dev/tvg/tlv /mnt/onsource"
        )
        out = machine.fail(
            f"dfdisk acquire {BY_ID['target-lvm']} --format raw -o /mnt/onsource/case -C CFTT -E SELF01 2>&1"
        )
        # dfdisk's device scan sees the LV mount on the source disk and stops first
        assert "Partitions are mounted" in out, out
        machine.succeed("test -z \"$(ls -A /mnt/onsource/case 2>/dev/null)\"")
        machine.succeed("umount /mnt/onsource && vgchange -q -an tvg")

        # A loop device backed by a file on the target disk: no mount on the source
        # is visible, so only the engine preflight (loop backing file -> disk) can stop it
        machine.succeed(f"dd if=/dev/zero of={dest}/backing.img bs=1M count=8 status=none")
        loop = machine.succeed(f"losetup -f --show {dest}/backing.img").strip()
        out = machine.fail(f"dfdisk acquire {loop} --format raw -o {dest}/loopcase -C CFTT -E LOOP01 2>&1")
        print(out)
        assert "Critical Safety Error" in out and target in out, out
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

    with subtest("dfinfo triage runs"):
        machine.succeed("dfinfo -p > /tmp/dfinfo.txt")
        machine.succeed("grep -q 'DFNIX FORENSIC SYSTEM TRIAGE REPORT' /tmp/dfinfo.txt")

    machine.succeed(f"sync && umount {dest}")
    machine.shutdown()

    with subtest("evidence images are bit-identical after the session"):
        changed = [d["name"] for d in EVIDENCE if sha256(image(d["name"])) != before[d["name"]]]
        assert not changed, f"evidence modified: {changed}"

    with subtest("negative control: writes to the unblocked target reach the image files"):
        assert sha256(image("target")) != before["target"]
  '';
}
