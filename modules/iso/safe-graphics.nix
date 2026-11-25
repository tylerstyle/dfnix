# Safe Graphics boot entry: boots with nomodeset directly into XFCE (X11)
# without requiring kernel command-line editing at the GRUB/isolinux prompt.
# Works identically on both the standard ISO and the NVIDIA Open ISO: forcing
# videoDrivers back to modesetting/fbdev disables hardware.nvidia in this
# specialisation, and forcing blockBlackwellNouveau keeps nouveau off Blackwell
# GPUs even alongside nomodeset.
{ lib, ... }:

{
  imports = [ ../hardware/gpu-quirks.nix ];

  specialisation.safe-graphics.configuration = {
    system.nixos.tags = [ "safe-graphics" ];

    isoImage.appendToMenuLabel = lib.mkForce " Forensic Acquisition OS, safe graphics: XFCE / nomodeset (Copy-to-RAM)";

    # vga=791 (1024x768x16 VESA framebuffer) ensures Legacy BIOS machines also
    # get a framebuffer under nomodeset; UEFI kernels ignore vga= and use GOP.
    boot.kernelParams = [ "nomodeset" "vga=791" ];

    dfnix.desktop.displayManager.defaultDesktop = lib.mkForce "xfce";
    dfnix.hardware.blockBlackwellNouveau = lib.mkForce true;
    services.xserver.videoDrivers = lib.mkForce [ "modesetting" "fbdev" ];
  };
}
