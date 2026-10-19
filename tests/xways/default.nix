{ pkgs }:

let
  # Build tiny mock xwforensics64.exe with mingw
  mockExe = pkgs.pkgsCross.mingwW64.stdenv.mkDerivation {
    name = "mock-xwforensics";
    dontUnpack = true;
    buildPhase = "$CC -O2 -o xwforensics64.exe ${./mock.c}";
    installPhase = "mkdir -p $out && cp xwforensics64.exe $out/";
  };
in
pkgs.testers.runNixOSTest {
  name = "dfnix-xways";

  nodes.machine = { pkgs, ... }: {
    imports = [
      ../../modules/forensics/wine-xways.nix
      ../../modules/release.nix
    ];

    dfnix.release.revision = "xways-test";
    dfnix.forensics.xways.enable = true;

    virtualisation.memorySize = 2048;

    # Allow scsi_debug module to simulate sda and sdb
    boot.kernelModules = [ "scsi_debug" ];
    boot.extraModprobeConfig = ''
      options scsi_debug dev_size_mb=64 num_tgts=2 inq_product=TEST_DISK
    '';

    environment.systemPackages = with pkgs; [
      dfcore
      jq
      util-linux
      coreutils
      gnugrep
    ];

    users.users.nixos = {
      isNormalUser = true;
      extraGroups = [ "wheel" "users" ];
    };

    security.sudo.wheelNeedsPassword = false;
  };

  testScript = ''
    import json
    import time

    machine.wait_for_unit("multi-user.target")

    # 1. Wait for simulated block devices: sda (protected system disk) and sdb (unprotected disk)
    machine.succeed("udevadm settle")
    machine.succeed("lsblk /dev/sda /dev/sdb")

    # 2. Set up /run/dfnix/protected.json protecting /dev/sda
    machine.succeed("mkdir -p /run/dfnix")
    sda_info = json.loads(machine.succeed("lsblk -J -p -o NAME,KNAME,MAJ:MIN,MODEL,SERIAL,WWN,SIZE,TYPE /dev/sda"))["blockdevices"][0]
    print(f"DEBUG sda_info: {sda_info}")
    sda_serial = sda_info.get("serial")

    protected_json = {
        "schema": 1,
        "generated_at": "2026-10-19T12:00:00Z",
        "devices": [
            {
                "role": "system_disk",
                "identity": {
                    # Purposely use a different path to verify protection matches by serial when present
                    "path": "/dev/sd_dummy_path",
                    "kernel_name": "sd_dummy_kname",
                    "serial": sda_serial or "TEST_SERIAL",
                },
                "reasons": ["Running system disk"]
            },
            {
                "role": "system_disk_fallback",
                "identity": {
                    # Protected entry without serial or wwn, verifying kernel-name fallback
                    "path": "/dev/sd_nonexistent",
                    "kernel_name": "sd_fallback",
                },
                "reasons": ["Fallback match by kernel name"]
            }
        ]
    }
    machine.succeed(f"cat << 'EOF' > /run/dfnix/protected.json\n{json.dumps(protected_json)}\nEOF")

    # 3. Test B3: -r / --res without value fails cleanly
    res_status, res_out = machine.execute("sudo -u nixos xways -r 2>&1")
    assert res_status != 0, f"Expected xways -r to fail, got status {res_status}"
    assert "requires a resolution argument" in res_out, f"Missing resolution error message in output: {res_out}"

    # 4. Test B4: Non-exe files are not selected as executable
    machine.succeed("touch /tmp/case.xfc")
    b4_status, b4_out = machine.execute("sudo -u nixos xways /tmp/case.xfc 2>&1")
    assert b4_status != 0, f"Expected non-exe to fail executable detection, got status {b4_status}"
    assert "No X-Ways executable found in trusted locations" in b4_out, f"Unexpected error for non-exe: {b4_out}"

    # 5. Test H2 Refusal: Binary under /media/evidence path
    machine.succeed("mkdir -p /media/evidence")
    machine.succeed("cp ${mockExe}/xwforensics64.exe /media/evidence/")
    evid_status, evid_out = machine.execute("sudo -u nixos xways /media/evidence/xwforensics64.exe 2>&1")
    assert evid_status != 0, f"Expected evidence path refusal, got {evid_status}"
    assert "Refusing to execute binary from evidence path" in evid_out, f"Missing evidence refusal message: {evid_out}"

    # 6. Test H2 Refusal: Binary on read-only filesystem
    machine.succeed("mkdir -p /media/target/smb_share")
    machine.succeed("mount -t tmpfs tmpfs /media/target/smb_share")
    machine.succeed("cp ${mockExe}/xwforensics64.exe /media/target/smb_share/")
    machine.succeed("mount -o remount,ro /media/target/smb_share")
    ro_status, ro_out = machine.execute("sudo -u nixos xways /media/target/smb_share/xwforensics64.exe 2>&1")
    assert ro_status != 0, f"Expected read-only refusal, got {ro_status}"
    assert "Refusing to execute binary on read-only filesystem" in ro_out, f"Missing ro refusal message: {ro_out}"

    # 7. Test H2 Untrusted path refusal and --trust-path override
    machine.succeed("mkdir -p /tmp/untrusted && cp ${mockExe}/xwforensics64.exe /tmp/untrusted/")
    untrusted_status, untrusted_out = machine.execute("sudo -u nixos xways /tmp/untrusted/xwforensics64.exe 2>&1")
    assert untrusted_status != 0, f"Expected untrusted path refusal, got {untrusted_status}"
    assert "Refusing to execute binary outside trusted application roots" in untrusted_out, f"Missing untrusted path message: {untrusted_out}"

    # Override with --trust-path
    override_status, override_out = machine.execute("sudo -u nixos xways --trust-path /tmp/untrusted/xwforensics64.exe 2>&1")
    assert override_status == 0, f"Expected --trust-path to succeed, got status {override_status}, output: {override_out}"
    assert "Examiner overridden path trust verification with --trust-path" in override_out, f"Missing override notice: {override_out}"

    # 8. Test Valid Launch: Place executable in /opt/xways and launch
    machine.succeed("mkdir -p /opt/xways && cp ${mockExe}/xwforensics64.exe /opt/xways/")
    t0 = time.time()
    launch_status, launch_out = machine.execute("sudo -u nixos xways /opt/xways/xwforensics64.exe 2>&1")
    elapsed = time.time() - t0
    print(f"X-Ways initial launch took {elapsed:.2f} seconds")

    assert launch_status == 0, f"Expected valid launch to succeed, got status {launch_status}, output: {launch_out}"

    # Verify SHA-256 output
    assert "SHA-256:" in launch_out, f"Missing SHA-256 output in: {launch_out}"

    # Verify H4 Protected drive skipping and raw drive mapping
    assert "Skipping protected system device: /dev/sda" in launch_out, f"Did not skip protected /dev/sda in: {launch_out}"
    assert "Mapped raw drive /dev/sdb" in launch_out, f"Did not map raw /dev/sdb in: {launch_out}"

    # Verify H1: Z: is absent, X: is present, cwd is X:\
    assert "DRIVE_X: present" in launch_out, f"Drive X: missing from Wine drives: {launch_out}"
    assert "DRIVE_Z: present" not in launch_out, f"Drive Z: should NOT be present: {launch_out}"
    assert "MOCK_CWD: X:\\" in launch_out, f"Expected CWD on X:\\, got: {launch_out}"

    # 9. Verify dfcore audit log integrity and records
    machine.succeed("dfcore-audit verify /run/dfnix/audit.jsonl")
    audit_lines = machine.succeed("cat /run/dfnix/audit.jsonl").strip().splitlines()
    assert len(audit_lines) >= 3, f"Expected at least 3 audit records, got {len(audit_lines)}"

    records = [json.loads(line) for line in audit_lines]
    outcomes = [r.get("outcome") for r in records]
    assert "refused" in outcomes, f"Expected at least one 'refused' outcome in audit records: {outcomes}"
    assert "ok" in outcomes, f"Expected at least one 'ok' outcome in audit records: {outcomes}"

    # Verify details of the successful launch
    ok_record = next(r for r in records if r.get("outcome") == "ok")
    assert ok_record["tool"] == "xways"
    assert ok_record["action"] == "launch"
    assert "sha256" in ok_record["details"]
    assert "drives" in ok_record["details"]
    assert "d" in ok_record["details"]["drives"]
    assert ok_record["details"]["drives"]["d"]["device"] == "/dev/sdb"

    # 10. Verify kernel-name fallback works when protected entry has neither serial nor wwn
    fallback_protected = {
        "schema": 1,
        "generated_at": "2026-10-19T12:00:00Z",
        "devices": [
            {
                "role": "system_disk",
                "identity": {
                    "path": "/dev/sdb",
                    "kernel_name": "sdb"
                },
                "reasons": ["Fallback match by kernel name"]
            }
        ]
    }
    machine.succeed(f"cat << 'EOF' > /run/dfnix/protected.json\n{json.dumps(fallback_protected)}\nEOF")
    fb_status, fb_out = machine.execute("sudo -u nixos xways /opt/xways/xwforensics64.exe 2>&1")
    assert fb_status == 0, f"Expected fallback test launch to succeed, got {fb_status}: {fb_out}"
    assert "Skipping protected system device: /dev/sdb" in fb_out, f"Kernel name fallback failed to skip /dev/sdb: {fb_out}"

    print("ALL X-WAYS LAUNCHER TESTS PASSED SUCCESSFULLY!")
  '';
}
