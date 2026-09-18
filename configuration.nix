{ config, pkgs, lib, ... }:

let
  forensicsOverlay = final: prev: {
    dfdisk = final.callPackage ./pkgs/dfdisk { };
    df-mount = final.callPackage ./pkgs/df-mount { };
    df-net = final.callPackage ./pkgs/df-net { };
    dwarf2json = final.callPackage ./pkgs/dwarf2json { };
    regripper = final.callPackage ./pkgs/regripper { };
  };
in
{
  imports = [
    # Base Live CD/DVD module (from nixpkgs channel)
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-base.nix>

    # df-nix Forensic Modules
    ./modules/iso/live-iso.nix
    ./modules/hardware/write-blocking.nix
    ./modules/forensics/default.nix
    ./modules/desktop/niri.nix
    ./modules/desktop/xfce.nix
    ./modules/desktop/display-manager.nix
  ];

  # Allow proprietary drivers & unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ forensicsOverlay ];

  # System package links & desktop launcher items
  environment.systemPackages = with pkgs; [
    dfdisk
    df-mount
    df-net
    
    # Desktop entries for TUI and GUI tools
    (makeDesktopItem {
      name = "dfdisk";
      desktopName = "dfdisk Forensic Imager";
      genericName = "Forensic Disk Imaging & Rescue TUI";
      comment = "Acquire E01/RAW images, rescue failing disks with ddrescue, and verify hashes";
      exec = "kitty --title 'dfdisk - Forensic Imager' -e sudo dfdisk";
      icon = "drive-harddisk-system";
      categories = [ "System" "Utility" ];
      keywords = [ "forensics" "evidence" "ddrescue" "e01" "imaging" "disk" ];
    })
    (makeDesktopItem {
      name = "dfmount";
      desktopName = "dfmount Forensic Storage TUI";
      genericName = "Forensic Disk Mounter TUI";
      comment = "Mount evidence write-blocked with zero journal replay or unblock target drives";
      exec = "kitty --title 'dfmount - Forensic Storage Manager' -e sudo dfmount";
      icon = "drive-harddisk-system";
      categories = [ "System" "Utility" ];
      keywords = [ "forensics" "mount" "writeblock" "target" "dfdisk" ];
    })
    (makeDesktopItem {
      name = "df-net";
      desktopName = "df-net Network Triage";
      genericName = "Forensic Network Operations";
      comment = "MAC spoofing, static IP setup (nmtui), network share mounting, and raw disk reception";
      exec = "kitty --title 'df-net - Forensic Network Operations' -e sudo df-net";
      icon = "network-workgroup";
      categories = [ "System" "Network" ];
      keywords = [ "forensics" "network" "macchanger" "nmtui" "smb" "nfs" ];
    })
  ];

  # Nix configuration (flakeless)
  nix.settings.experimental-features = [ "nix-command" ];
}
