# Headless boot entry for servers (roadmap §3.3): booted through the BMC's
# virtual media (iDRAC, iLO, XClarity, IPMI) or from USB, and used over the
# BMC's serial-over-LAN or a serial cable.
#
# A specialisation, so the ISO shows it as its own boot entry. Kernel and
# boot messages go to the screen and to both serial ports (BMCs redirect COM1
# or COM2), with a login prompt on each port that exists. No graphical
# session: servers often have only the BMC's small framebuffer. Everything
# else, write-blocking included, is the same system.
{ lib, ... }:

{
  specialisation.headless.configuration = {
    system.nixos.tags = [ "headless" ];

    # The last console= is /dev/console; the others get kernel messages too
    boot.kernelParams = [
      "console=tty0"
      "console=ttyS1,115200n8"
      "console=ttyS0,115200n8"
    ];

    # No graphical session at all: the desktop modules would otherwise still
    # enable X, and NixOS would start LightDM and graphical.target
    dfnix.desktop.displayManager.enable = lib.mkForce false;
    dfnix.desktop.xfce.enable = lib.mkForce false;
    dfnix.desktop.niri.enable = lib.mkForce false;
    services.xserver.enable = lib.mkForce false;

    # Login prompts: systemd's getty generator starts one on every serial
    # console that is active, so a missing COM2 doesn't hold up the boot
  };
}
