{
  description = "dfnix: Live Bootable NixOS Distribution Tuned for Forensic Field Work";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Forensic Disk Imager by Tylerstyle
    dfdisk = {
      url = "github:tylerstyle/dfdisk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, dfdisk, ... }@inputs:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Custom packages overlay
      forensicsOverlay = final: prev: {
        # dfdisk from flake input or fallback to local derivation
        dfdisk = dfdisk.packages.${prev.stdenv.hostPlatform.system}.default;
        
        # Dedicated Forensic Mounter & Target Unblocker
        dfmount = final.callPackage ./pkgs/dfmount { };

        # Dedicated Forensic Network Operations & Triage
        dfnet = final.callPackage ./pkgs/dfnet { };

        # Forensic System Triage & Fastfetch Reporter
        dfinfo = final.callPackage ./pkgs/dfinfo { };

        # Volatility 3 ISF generator
        dwarf2json = final.callPackage ./pkgs/dwarf2json { };

        # Windows Registry parser
        regripper = final.callPackage ./pkgs/regripper { };
      };
    in
    {
      # Export custom packages for direct build / shell
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ forensicsOverlay ];
            config.allowUnfree = true;
          };
        in
        {
          inherit (pkgs) dfdisk dfmount dfnet dfinfo dwarf2json regripper;
          
          # Shortcut: nix build .#iso
          iso = self.nixosConfigurations.df-forensics-iso.config.system.build.isoImage;

          # Fast prototyping VM shortcut: nix build .#vm
          vm = self.nixosConfigurations.df-forensics-iso.config.system.build.vm;
        }
      );

      # NixOS System Configurations
      nixosConfigurations = {
        # Target 1: Bootable Live Forensic ISO Image
        # Build command: nix build .#nixosConfigurations.df-forensics-iso.config.system.build.isoImage
        df-forensics-iso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            # Base installation CD/DVD configuration (without calamares disk polling)
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-base.nix"

            # Apply forensics package overlay
            {
              nixpkgs.overlays = [ forensicsOverlay ];
              nixpkgs.config.allowUnfree = true;
            }

            # Project modules
            ./modules/iso/live-iso.nix
            ./modules/hardware/write-blocking.nix
            ./modules/forensics/default.nix
            ./modules/forensics/wine-xways.nix
            ./modules/desktop/niri.nix
            ./modules/desktop/xfce.nix
            ./modules/desktop/display-manager.nix

            # Global desktop application entries & branding icons
            ({ pkgs, ... }: {
              environment.systemPackages = [
                (pkgs.makeDesktopItem {
                  name = "dfdisk";
                  desktopName = "dfdisk Forensic Imager";
                  genericName = "Forensic Disk Imaging & Rescue TUI";
                  comment = "Acquire E01/RAW images, rescue failing disks with ddrescue, and verify hashes";
                  exec = "kitty --title \"dfdisk - Forensic Imager\" sudo dfdisk";
                  icon = "drive-harddisk-system";
                  categories = [ "System" "Utility" ];
                  keywords = [ "forensics" "evidence" "ddrescue" "e01" "imaging" "disk" ];
                })
                (pkgs.makeDesktopItem {
                  name = "dfmount";
                  desktopName = "dfmount Forensic Storage TUI";
                  genericName = "Forensic Disk Mounter TUI";
                  comment = "Mount evidence write-blocked with zero journal replay or unblock target drives";
                  exec = "kitty --title \"dfmount - Forensic Storage Manager\" sudo dfmount";
                  icon = "drive-harddisk-system";
                  categories = [ "System" "Utility" ];
                  keywords = [ "forensics" "mount" "writeblock" "target" "dfdisk" ];
                })
                (pkgs.makeDesktopItem {
                  name = "dfnet";
                  desktopName = "dfnet Network Triage";
                  genericName = "Forensic Network Operations";
                  comment = "MAC spoofing, static IP setup (nmtui), network share mounting, and raw disk reception";
                  exec = "kitty --title \"dfnet - Forensic Network Operations\" sudo dfnet";
                  icon = "network-workgroup";
                  categories = [ "System" "Network" ];
                  keywords = [ "forensics" "network" "macchanger" "nmtui" "smb" "nfs" ];
                })
                (pkgs.makeDesktopItem {
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
            })
          ];
        };

        # Target 2: Persistent Lab Workstation Profile
        df-forensics-workstation = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            {
              nixpkgs.overlays = [ forensicsOverlay ];
              nixpkgs.config.allowUnfree = true;
            }
            ./modules/hardware/write-blocking.nix
            ./modules/forensics/default.nix
            ./modules/desktop/niri.nix
            ./modules/desktop/xfce.nix
            ./modules/desktop/display-manager.nix
          ];
        };
      };
    };
}
