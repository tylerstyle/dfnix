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

    dfinfo = if builtins.pathExists ../dfinfo/package.nix
             then final.callPackage ../dfinfo/package.nix { }
             else final.callPackage ./pkgs/dfinfo { };

    dfnix-guide = final.callPackage ./pkgs/dfnix-guide { };

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
    dfinfo
    dfnix-guide
    firefox
    chromium
    
    # Desktop entries for TUI tools (Kitty launches directly without legacy -e flag)
    (makeDesktopItem {
      name = "dfnix-guide";
      desktopName = "dfnix Quick Start Guide";
      genericName = "Forensic Quick Start & Navigation Guide";
      comment = "Guide for storage mounting, hardware triage, disk imaging, and Niri navigation";
      exec = "dfnix-guide";
      icon = "help-browser";
      categories = [ "System" "Documentation" "Utility" ];
      keywords = [ "guide" "help" "documentation" "quickstart" "niri" "dfdisk" "dfmount" "dfinfo" "forensics" ];
    })
    (makeDesktopItem {
      name = "dfdisk";
      desktopName = "dfdisk Forensic Imager";
      genericName = "Forensic Disk Imaging & Rescue TUI";
      comment = "Acquire E01/RAW images, rescue failing disks with ddrescue, and verify hashes";
      exec = "kitty --title \"dfdisk - Forensic Imager\" sudo dfdisk";
      icon = "drive-harddisk-system";
      categories = [ "System" "Utility" ];
      keywords = [ "forensics" "evidence" "ddrescue" "e01" "imaging" "disk" ];
    })
    (makeDesktopItem {
      name = "dfmount";
      desktopName = "dfmount Forensic Storage TUI";
      genericName = "Forensic Disk Mounter TUI";
      comment = "Mount evidence write-blocked with zero journal replay or unblock target drives";
      exec = "kitty --title \"dfmount - Forensic Storage Manager\" sudo dfmount";
      icon = "drive-harddisk-system";
      categories = [ "System" "Utility" ];
      keywords = [ "forensics" "mount" "writeblock" "target" "dfdisk" ];
    })
    (makeDesktopItem {
      name = "dfnet";
      desktopName = "dfnet Network Triage";
      genericName = "Forensic Network Operations";
      comment = "MAC spoofing, static IP setup (nmtui), network share mounting, and raw disk reception";
      exec = "kitty --title \"dfnet - Forensic Network Operations\" sudo dfnet";
      icon = "network-workgroup";
      categories = [ "System" "Network" ];
      keywords = [ "forensics" "network" "macchanger" "nmtui" "smb" "nfs" ];
    })
    (makeDesktopItem {
      name = "dfinfo";
      desktopName = "dfinfo Forensic Triage";
      genericName = "Forensic System Triage & Fastfetch";
      comment = "System hardware triage, fastfetch overview, and concise forensic documentation";
      exec = "kitty --title \"dfinfo - Forensic System Triage\" sudo dfinfo";
      icon = "utilities-system-monitor";
      categories = [ "System" "Utility" ];
      keywords = [ "forensics" "triage" "fastfetch" "system" "hardware" "evidence" ];
    })
  ];

  # Starship cross-shell prompt for examiner shell
  programs.starship = {
    enable = true;
    presets = [ ];
  };
  programs.bash.completion.enable = true;

  # Hardware Graphics & Mesa DRI acceleration (required for Niri Wayland and SDDM)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # X11 server subsystem for fallback and modesetting drivers
  services.xserver = {
    enable = true;
    xkb = {
      layout = "de,us";
      options = "grp:alt_shift_toggle";
      variant = "";
    };
  };

  # System fonts for Noctalia UI, Kitty terminal, and forensic glyphs
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    nerd-fonts.fira-code
    nerd-fonts.symbols-only
  ];

  # Nix configuration (flakeless)
  nix.settings.experimental-features = [ "nix-command" ];

  # Rapid Prototyping VM resources (applied when building system.build.vm)
  virtualisation.vmVariant = {
    virtualisation.memorySize = 8192; # 8 GiB RAM
    virtualisation.cores = 4;         # 4 CPU cores
    virtualisation.efi.OVMF = pkgs.OVMF // { systemManagementModeRequired = false; };
    boot.kernelParams = lib.mkVMOverride [ "panic=10" ]; # Skip copytoram in VM closure
    boot.initrd.systemd.services.copytoram.enable = false;
  };
}
