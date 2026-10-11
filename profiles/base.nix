# Every dfnix system: write-blocking, protected-device registry, release stamp,
# forensic tool suites and both desktops. Expects the dfnix package overlay.
{
  imports = [
    ../modules/hardware/write-blocking.nix
    ../modules/hardware/protected-devices.nix
    ../modules/release.nix
    ../modules/forensics/default.nix
    ../modules/forensics/wine-xways.nix
    ../modules/desktop/niri.nix
    ../modules/desktop/xfce.nix
    ../modules/desktop/display-manager.nix
    ../modules/desktop/entries.nix
    ../modules/desktop/common-gui.nix
  ];

  nixpkgs.config.allowUnfree = true;
}
