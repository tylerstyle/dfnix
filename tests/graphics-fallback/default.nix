# Graphics fallback & Blackwell GPU quirk regression test (KVM).
#
# Verifies:
# 1. Booting with `nomodeset` on `defaultDesktop = "niri"` (the `Options -> No
#    modesetting` path) automatically bypasses Niri past TTY1 autologin and
#    brings up a live Xorg + XFCE session (fixing the dead-code stall).
# 2. The priority-70 Blackwell nouveau `driver_override` udev rule is installed,
#    passes `udevadm verify`, and matches NVIDIA display IDs >= 0x2900 while
#    leaving Ada (<= 0x28ff), older NVIDIA, non-display functions, and other
#    vendors untouched.
# 3. `dfnix-gpu-probe` classifies single-GPU, dual-GPU (disconnected iGPU +
#    connected simple-framebuffer), NVIDIA Open, nomodeset, legacy fbdev-only,
#    and cmdline-boundary topologies accurately and produces a valid runtime
#    Xorg override config preserving Fonts/ModulePath/InputClass.
{ pkgs }:

let
  gpuProbeUnitTests = pkgs.writeText "test-gpu-probe.py" ''
    import os
    import shutil
    import subprocess
    import tempfile


    def run_probe(args, drm_dir, cmdline_text):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write(cmdline_text + "\n")
            cmd_path = f.name
        try:
            env = os.environ.copy()
            env["DFNIX_SYSFS_DRM"] = drm_dir
            env["DFNIX_PROC_CMDLINE"] = cmd_path
            return subprocess.run(
                ["dfnix-gpu-probe"] + args, env=env, capture_output=True, text=True
            )
        finally:
            os.unlink(cmd_path)


    def make_card(root, drv_root, card, driver, connectors):
        cdir = os.path.join(root, card)
        os.makedirs(os.path.join(cdir, "device"), exist_ok=True)
        if driver is not None:
            ddir = os.path.join(drv_root, driver)
            os.makedirs(ddir, exist_ok=True)
            os.symlink(ddir, os.path.join(cdir, "device", "driver"))
        for conn, status in connectors.items():
            condir = os.path.join(cdir, f"{card}-{conn}")
            os.makedirs(condir, exist_ok=True)
            with open(os.path.join(condir, "status"), "w") as f:
                f.write(status + "\n")


    base = tempfile.mkdtemp(prefix="dfnix-gpu-test-")
    try:
        drvs = os.path.join(base, "drivers")

        # Case A: Dual-GPU (i915 disconnected + simple-framebuffer connected)
        drm_a = os.path.join(base, "case_a")
        make_card(drm_a, drvs, "card0", "i915", {"HDMI-A-1": "disconnected", "DP-1": "disconnected"})
        make_card(drm_a, drvs, "card1", "simple-framebuffer", {"Unknown-1": "connected"})
        r1 = run_probe(["should-use-niri"], drm_a, "copytoram panic=10")
        assert r1.returncode != 0, f"Case A should skip Niri, got rc={r1.returncode}"
        r2 = run_probe(["simpledrm-card"], drm_a, "copytoram panic=10")
        assert r2.returncode == 0 and r2.stdout.strip() == "/dev/dri/card1", (
            f"Case A wrong simpledrm card: {r2.returncode} {r2.stdout!r}"
        )

        # Case B: Dual-GPU with onboard Intel HDMI connected
        drm_b = os.path.join(base, "case_b")
        make_card(drm_b, drvs, "card0", "i915", {"HDMI-A-1": "connected", "DP-1": "disconnected"})
        make_card(drm_b, drvs, "card1", "simple-framebuffer", {"Unknown-1": "disconnected"})
        r1 = run_probe(["should-use-niri"], drm_b, "copytoram panic=10")
        assert r1.returncode == 0, f"Case B should use Niri, got rc={r1.returncode}"
        r2 = run_probe(["simpledrm-card"], drm_b, "copytoram panic=10")
        assert r2.returncode != 0, f"Case B should not pin simpledrm, got {r2.stdout!r}"

        # Case C: NVIDIA Open ISO with NVIDIA HDMI connected + disconnected iGPU
        drm_c = os.path.join(base, "case_c")
        make_card(drm_c, drvs, "card0", "i915", {"HDMI-A-1": "disconnected"})
        make_card(drm_c, drvs, "card1", "nvidia", {"HDMI-A-1": "connected"})
        r1 = run_probe(["should-use-niri"], drm_c, "copytoram panic=10")
        assert r1.returncode == 0, f"Case C (nvidia) should use Niri, got rc={r1.returncode}"
        r2 = run_probe(["simpledrm-card"], drm_c, "copytoram panic=10")
        assert r2.returncode != 0, f"Case C should not pin simpledrm, got {r2.stdout!r}"

        # Case D: nomodeset + simple-framebuffer only
        drm_d = os.path.join(base, "case_d")
        make_card(drm_d, drvs, "card0", "simple-framebuffer", {"Unknown-1": "connected"})
        r1 = run_probe(["should-use-niri"], drm_d, "copytoram nomodeset panic=10")
        assert r1.returncode != 0, "Case D should skip Niri under nomodeset"
        r2 = run_probe(["simpledrm-card"], drm_d, "copytoram nomodeset panic=10")
        assert r2.returncode == 0 and r2.stdout.strip() == "/dev/dri/card0", (
            f"Case D wrong card: {r2.stdout!r}"
        )

        # Case E: Legacy BIOS nomodeset (no /dev/dri/card* at all)
        drm_e = os.path.join(base, "case_e")
        os.makedirs(drm_e, exist_ok=True)
        r1 = run_probe(["should-use-niri"], drm_e, "copytoram nomodeset")
        assert r1.returncode != 0, "Case E should skip Niri with no DRM cards"
        r2 = run_probe(["simpledrm-card"], drm_e, "copytoram nomodeset")
        assert r2.returncode != 0, "Case E should not emit simpledrm card when none exists"

        # Case F: Substring cmdline boundary (foo.nomodeset=1 must NOT trigger nomodeset)
        drm_f = os.path.join(base, "case_f")
        make_card(drm_f, drvs, "card0", "virtio_gpu", {"Virtual-1": "connected"})
        r1 = run_probe(["should-use-niri"], drm_f, "copytoram foo.nomodeset=1 panic=10")
        assert r1.returncode == 0, "Case F false-positive on substring nomodeset"

        # Case G: make-xorg-conf on real /etc/X11/xorg.conf + synthetic nvidia ServerLayout
        out_conf = os.path.join(base, "xorg-simpledrm.conf")
        subprocess.run(
            ["dfnix-gpu-probe", "make-xorg-conf", "/etc/X11/xorg.conf", "/dev/dri/card1", out_conf],
            check=True,
        )
        txt = open(out_conf).read()
        assert 'Section "Files"' in txt
        assert 'Section "InputClass"' in txt
        assert 'Option "AutoAddGPU" "false"' in txt
        assert 'Option "AutoBindGPU" "false"' in txt
        assert 'Option "kmsdev" "/dev/dri/card1"' in txt
        assert 'Option "AccelMethod" "none"' in txt
        assert 'Screen "Screen-modesetting[0]"' in txt

        nv_in = os.path.join(base, "xorg-nv-in.conf")
        nv_out = os.path.join(base, "xorg-nv-out.conf")
        with open(nv_in, "w") as f:
            f.write(
                open("/etc/X11/xorg.conf").read().replace(
                    'Screen "Screen-modesetting[0]"',
                    'Screen "Screen-nvidia[0]"\n  Screen "Screen-modesetting[0]"',
                )
            )
        subprocess.run(
            ["dfnix-gpu-probe", "make-xorg-conf", nv_in, "/dev/dri/card1", nv_out],
            check=True,
        )
        nv_txt = open(nv_out).read()
        assert 'Screen "Screen-nvidia[0]"' not in nv_txt, (
            "make-xorg-conf must drop Screen-nvidia from ServerLayout"
        )
        assert 'Screen "Screen-modesetting[0]"' in nv_txt
        assert 'Option "kmsdev" "/dev/dri/card1"' in nv_txt
    finally:
        shutil.rmtree(base)
    print("ALL DFNIX-GPU-PROBE UNIT CASES PASSED!")
  '';
in
pkgs.testers.runNixOSTest {
  name = "dfnix-graphics-fallback";

  nodes.machine = { lib, pkgs, ... }: {
    imports = [
      ../../modules/hardware/gpu-quirks.nix
      ../../modules/desktop/niri.nix
      ../../modules/desktop/xfce.nix
      ../../modules/desktop/display-manager.nix
    ];

    # Lightweight VM config without pulling browsers into the test closure
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    virtualisation.graphics = true;

    hardware.graphics.enable = true;

    # Exercise the exact Safe Graphics kernel parameters ("nomodeset" "vga=791")
    # on defaultDesktop = "niri" (also covering "Options -> No modesetting").
    # vga=791 (0x317, 1024x768x16) hands Linux a VESA framebuffer on Legacy BIOS
    # / direct-boot QEMU so CONFIG_DRM_SIMPLEDRM=y exposes a real /dev/dri/card0
    # (simple-framebuffer), matching UEFI GOP on bare metal.
    boot.kernelParams = [ "nomodeset" "vga=791" ];

    dfnix.desktop.displayManager = {
      enable = true;
      autologin = true;
      autologinUser = "nixos";
      defaultDesktop = "niri";
    };

    users.users.nixos = {
      isNormalUser = true;
      extraGroups = [ "wheel" "video" "audio" "input" ];
      initialHashedPassword = "";
    };
    security.sudo.wheelNeedsPassword = false;

    environment.systemPackages = with pkgs; [
      procps
      python3
      xdpyinfo
    ];

    # Keep test VM independent of systemd-networkd wait
    systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;
  };

  testScript = ''
    import fnmatch
    import re

    machine.wait_for_unit("multi-user.target")

    # 1. Confirm nomodeset is active and dfnix-gpu-probe bypasses Niri
    cmdline = machine.succeed("cat /proc/cmdline")
    assert "nomodeset" in cmdline.split(), f"Expected nomodeset in /proc/cmdline: {cmdline}"

    rc, _ = machine.execute("dfnix-gpu-probe should-use-niri")
    assert rc != 0, "Expected dfnix-gpu-probe should-use-niri to fail under nomodeset"

    # 2. Verify kernel simple-framebuffer DRM card is exposed and TTY1 autologin
    #    lands cleanly in a live Xorg + XFCE session using our runtime Xorg override
    card = machine.succeed("dfnix-gpu-probe simpledrm-card").strip()
    assert card.startswith("/dev/dri/card"), f"Expected simpledrm card, got: {card!r}"
    drv = machine.succeed(f"basename $(readlink -f /sys/class/drm/{card.split('/')[-1]}/device/driver)").strip()
    assert drv == "simple-framebuffer", f"Expected simple-framebuffer driver, got: {drv!r}"

    try:
        machine.wait_until_succeeds("pgrep -u nixos -x X", timeout=60)
        machine.wait_until_succeeds("pgrep -u nixos -f xfce4-session", timeout=60)
        machine.wait_until_succeeds("pgrep -u nixos -f xfwm4", timeout=60)
        machine.wait_until_succeeds("test -S /tmp/.X11-unix/X0", timeout=30)
        machine.succeed("sudo -u nixos DISPLAY=:0 xdpyinfo >/dev/null")
    except Exception:
        print("=== DIAGNOSTIC: nixos processes ===")
        print(machine.execute("ps -u nixos -o pid,comm,args 2>&1 || true")[1])
        print("=== DIAGNOSTIC: /dev/dri & /dev/fb* ===")
        print(machine.execute("ls -la /dev/dri /dev/fb* 2>&1")[1])
        print("=== DIAGNOSTIC: Xorg log ===")
        print(machine.execute("cat /home/nixos/.local/share/xorg/Xorg.0.log 2>&1 || true")[1])
        print("=== DIAGNOSTIC: runtime xorg override ===")
        print(machine.execute("cat /run/user/1000/dfnix-xorg-simpledrm.conf 2>&1 || true")[1])
        raise

    # Confirm our runtime simpledrm Xorg config was generated and passed to Xorg
    xorg_pid = machine.succeed("pgrep -u nixos -x X | head -n1").strip()
    xorg_cmd = machine.succeed(f"tr '\\0' ' ' < /proc/{xorg_pid}/cmdline")
    assert "dfnix-xorg-simpledrm.conf" in xorg_cmd, f"Expected runtime simpledrm Xorg config in cmdline: {xorg_cmd}"

    # Verify Xorg actually loaded our runtime override with AutoAddGPU disabled
    xorg_log = machine.succeed("cat /home/nixos/.local/share/xorg/Xorg.0.log")
    assert 'Using config file: "/run/user/1000/dfnix-xorg-simpledrm.conf"' in xorg_log, "Xorg did not use runtime simpledrm config"
    assert "Not automatically adding GPU devices" in xorg_log, "Xorg did not apply AutoAddGPU false"

    niri_rc, _ = machine.execute("pgrep -x niri")
    assert niri_rc != 0, "niri should not be running under nomodeset"

    # 3. Verify 70-dfnix-gpu-quirks.rules is installed, valid, and matches only Blackwell+ display IDs
    rule_path = "/etc/udev/rules.d/70-dfnix-gpu-quirks.rules"
    machine.succeed(f"test -r {rule_path}")
    machine.succeed(f"udevadm verify {rule_path}")

    rule_text = machine.succeed(f"cat {rule_path}")
    rule_lines = [l.strip() for l in rule_text.splitlines() if l.strip() and not l.strip().startswith("#")]
    assert len(rule_lines) == 1, f"Expected 1 active udev rule line, got {rule_lines}"
    rule = rule_lines[0]
    assert 'ATTR{driver_override}="dfnix-no-nouveau"' in rule, f"Missing driver_override in rule: {rule}"
    assert "MODALIAS" not in rule, f"Rule must not touch MODALIAS: {rule}"

    m_vendor = re.search(r'ATTR\{vendor\}=="([^"]+)"', rule)
    m_class = re.search(r'ATTR\{class\}=="([^"]+)"', rule)
    m_dev = re.search(r'ATTR\{device\}=="([^"]+)"', rule)
    assert m_vendor and m_class and m_dev, f"Failed to parse ATTR clauses from rule: {rule}"

    vendor_pat = m_vendor.group(1)
    class_pat = m_class.group(1)
    dev_pats = m_dev.group(1).split("|")

    def matches_rule(vendor, pci_class, device):
        return (
            fnmatch.fnmatchcase(vendor, vendor_pat)
            and fnmatch.fnmatchcase(pci_class, class_pat)
            and any(fnmatch.fnmatchcase(device, p) for p in dev_pats)
        )

    # Must match: Blackwell & newer NVIDIA display controllers (0x2900..0xffff)
    for dev in ("0x2900", "0x2b85", "0x2c02", "0x2d04", "0x2d83", "0x2d98", "0x2dd8", "0x2f04", "0x3000", "0xffff"):
        assert matches_rule("0x10de", "0x030000", dev), f"Rule failed to match Blackwell VGA {dev}"
        assert matches_rule("0x10de", "0x030200", dev), f"Rule failed to match Blackwell 3D {dev}"

    # Must NOT match: Ada Lovelace (ends at 0x28f8) and earlier NVIDIA GPUs
    for dev in ("0x28f8", "0x28ff", "0x2860", "0x2684", "0x2204", "0x1e04", "0x1b80"):
        assert not matches_rule("0x10de", "0x030000", dev), f"Rule falsely matched pre-Blackwell {dev}"

    # Must NOT match: NVIDIA non-display functions (HDA audio, USB-C) or other vendors
    assert not matches_rule("0x10de", "0x040300", "0x2f80"), "Rule falsely matched NVIDIA HDA audio"
    assert not matches_rule("0x10de", "0x0c0330", "0x2d83"), "Rule falsely matched USB controller"
    assert not matches_rule("0x8086", "0x030000", "0x7d55"), "Rule falsely matched Intel GPU"
    assert not matches_rule("0x1002", "0x030000", "0x744c"), "Rule falsely matched AMD GPU"

    # 4. Unit-test dfnix-gpu-probe across all GPU topologies & Xorg config overrides
    machine.succeed("python3 ${gpuProbeUnitTests}")

    print("ALL GRAPHICS FALLBACK & BLACKWELL UDEV TESTS PASSED!")
  '';
}
