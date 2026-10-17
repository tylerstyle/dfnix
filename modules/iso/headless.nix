# Headless boot entry for servers (roadmap §3.3): booted through the BMC's
# virtual media (iDRAC, iLO, XClarity, IPMI) or from USB, and used over the
# BMC's serial-over-LAN or a serial cable.
#
# A specialisation, so the ISO shows it as its own boot entry. Kernel and
# boot messages go to the screen and to COM2, where most BMCs redirect
# serial-over-LAN (iDRAC, iLO and Supermicro by default). Linux binds only one
# console per driver, so they can't go to COM1 as well. A login prompt runs on
# COM1 and COM2. No graphical session: servers often have only the BMC's small
# framebuffer. Everything else, write-blocking included, is the same system.
{ lib, ... }:

{
  specialisation.headless.configuration = {
    system.nixos.tags = [ "headless" ];

    # Its own name in the boot menus (isolinux and GRUB); otherwise it would
    # carry the default entry's label
    isoImage.appendToMenuLabel = lib.mkForce " Forensic Acquisition OS, headless: serial console (Copy-to-RAM)";

    # The last console= is /dev/console (systemd's status output). One serial
    # console only: a second console=ttySx would be ignored
    boot.kernelParams = [
      "console=tty0"
      "console=ttyS1,115200n8"
    ];

    # No graphical session at all: the desktop modules would otherwise still
    # enable X, and NixOS would start LightDM and graphical.target
    dfnix.desktop.displayManager.enable = lib.mkForce false;
    dfnix.desktop.xfce.enable = lib.mkForce false;
    dfnix.desktop.niri.enable = lib.mkForce false;
    services.xserver.enable = lib.mkForce false;

    # Login prompts: systemd's getty generator starts one on the active serial
    # console (COM2); COM1 (the physical port, serial cables, BMCs set to COM1)
    # gets its own, the way NixOS starts autovt@tty1
    systemd.targets.getty.wants = [ "serial-getty@ttyS0.service" ];
  };
}
