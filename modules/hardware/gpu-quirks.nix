{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dfnix.hardware;

  gpuQuirksUdevPackage = pkgs.writeTextFile {
    name = "70-dfnix-gpu-quirks.rules";
    destination = "/etc/udev/rules.d/70-dfnix-gpu-quirks.rules";
    text = ''
      # ==============================================================================
      # dfnix Hardware GPU Quirks (Priority 70 — evaluated before 80-drivers.rules)
      # ==============================================================================
      # Prevent nouveau from binding to NVIDIA Blackwell (GB10x/GB20x, RTX 50-series)
      # and newer PCI display controllers (PCI device ID >= 0x2900; Ada Lovelace ends
      # at 0x28f8 in hwdata pci.ids). On Linux 6.18, nouveau's KMS takeover freezes
      # Blackwell HDMI output; setting driver_override leaves UEFI GOP simpledrm
      # active at native resolution for the XFCE fallback while leaving pre-Blackwell
      # NVIDIA, Intel, and AMD GPUs untouched.
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03*", ATTR{device}=="0x2[9a-f][0-9a-f][0-9a-f]|0x[3-9a-f][0-9a-f][0-9a-f][0-9a-f]", ATTR{driver_override}="dfnix-no-nouveau"
    '';
  };
in
{
  options.dfnix.hardware.blockBlackwellNouveau = mkOption {
    type = types.bool;
    default = true;
    description = ''
      Prevent the in-tree nouveau driver from binding to NVIDIA Blackwell
      (PCI device ID >= 0x2900) and newer display controllers via a priority-70
      udev driver_override rule. Set to false in profiles that load nvidia-open.
    '';
  };

  config = mkIf cfg.blockBlackwellNouveau {
    # Install in both stage 1 (initrd) and stage 2 so driver_override is set
    # before 80-drivers.rules triggers kmod loading in stage 2.
    services.udev.packages = [ gpuQuirksUdevPackage ];
    boot.initrd.services.udev.packages = [ gpuQuirksUdevPackage ];
  };
}
