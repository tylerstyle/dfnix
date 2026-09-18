{ config, pkgs, lib, ... }:

let
  forensicsOverlay = final: prev: {
    # Live workspace ingestion: Ingests current local git repos if present
    dfdisk = if builtins.pathExists ../dfdisk/package.nix
             then final.callPackage ../dfdisk/package.nix { }
             else final.callPackage ./pkgs/dfdisk { };

    dfmount = if builtins.pathExists ../dfmount/package.nix
              then final.callPackage ../dfmount/package.nix { }
              else final.callPackage ./pkgs/dfmount { };

    dfnet = if builtins.pathExists ../dfnet/package.nix
            then final.callPackage ../dfnet/package.nix { }
            else final.callPackage ./pkgs/dfnet { };

    dwarf2json = final.callPackage ./pkgs/dwarf2json { };
    regripper = final.callPackage ./pkgs/regripper { };
  };
in
{
  imports = [
    # Base Live CD/DVD module (from nixpkgs channel)
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-base.nix>

    # dfnix Forensic Modules
    ./modules/iso/live-iso.nix
    ./modules/hardware/write-blocking.nix
    ./modules/forensics/default.nix
    ./modules/forensics/wine-xways.nix
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
    dfmount
    dfnet
    
    # Desktop entries for TUI tools
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
      name = "dfnet";
      desktopName = "dfnet Network Triage";
      genericName = "Forensic Network Operations";
      comment = "MAC spoofing, static IP setup (nmtui), network share mounting, and raw disk reception";
      exec = "kitty --title 'dfnet - Forensic Network Operations' -e sudo dfnet";
      icon = "network-workgroup";
      categories = [ "System" "Network" ];
      keywords = [ "forensics" "network" "macchanger" "nmtui" "smb" "nfs" ];
    })
  ];

  # Nix configuration (flakeless)
  nix.settings.experimental-features = [ "nix-command" ];
}
