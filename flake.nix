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

        # Forensic Quick Start & Navigation Guide
        dfnix-guide = final.callPackage ./pkgs/dfnix-guide { };

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
          inherit (pkgs) dfdisk dfmount dfnet dfinfo dfnix-guide dwarf2json regripper;
          
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

            # Base desktop environment, graphics, fonts, and VM variant
            ({ pkgs, ... }: {
              # Hardware Mesa DRI Graphics Acceleration
              hardware.graphics = {
                enable = true;
                enable32Bit = true;
              };

              # Keyboard layout
              services.xserver.xkb = {
                layout = "de,us";
                options = "grp:alt_shift_toggle";
              };

              # Fonts for Noctalia UI, Kitty terminal & forensic glyphs
              fonts.packages = with pkgs; [
                noto-fonts
                noto-fonts-cjk-sans
                noto-fonts-color-emoji
                nerd-fonts.fira-code
                nerd-fonts.symbols-only
              ];

              # Additional system packages
              environment.systemPackages = with pkgs; [
                firefox
                chromium
              ];

              # Starship prompt
              programs.starship = {
                enable = true;
                presets = [ ];
              };
              programs.bash.completion.enable = true;

              # Rapid Prototyping VM resources (applied when building system.build.vm)
              virtualisation.vmVariant = {
                virtualisation.memorySize = 8192; # 8 GiB RAM
                virtualisation.cores = 4;         # 4 CPU cores
                virtualisation.efi.OVMF = pkgs.OVMF // { systemManagementModeRequired = false; };
                boot.kernelParams = nixpkgs.lib.mkVMOverride [ "panic=10" ]; # Skip copytoram in VM closure
                boot.initrd.systemd.services.copytoram.enable = false;
              };
            })

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
                (pkgs.makeDesktopItem {
                  name = "dfnix-guide";
                  desktopName = "dfnix Quick Start Guide";
                  genericName = "Forensic Quick Start & Navigation Guide";
                  comment = "Guide for storage mounting, hardware triage, disk imaging, and Niri navigation";
                  exec = "dfnix-guide";
                  icon = "help-browser";
                  categories = [ "System" "Documentation" "Utility" ];
                  keywords = [ "guide" "help" "documentation" "quickstart" "niri" "dfdisk" "dfmount" "dfinfo" "forensics" ];
                })
              ];
            })
          ];
        };

        # Target 2: Persistent Lab Workstation Profile (Standalone test configuration)
        df-forensics-workstation = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            self.nixosModules.workstation
            {
              system.stateVersion = "24.11";
              boot.loader.grub.devices = [ "/dev/sda" ];
              fileSystems."/" = {
                device = "/dev/disk/by-label/nixos";
                fsType = "ext4";
              };
            }
          ];
        };
      };

      # Export reusable NixOS modules for persistent installations
      nixosModules = {
        forensics = ./modules/forensics/default.nix;
        writeBlocking = ./modules/hardware/write-blocking.nix;
        niri = ./modules/desktop/niri.nix;
        xfce = ./modules/desktop/xfce.nix;
        displayManager = ./modules/desktop/display-manager.nix;
        liveIso = ./modules/iso/live-iso.nix;
        wineXways = ./modules/forensics/wine-xways.nix;

        workstation = { pkgs, ... }: {
          nixpkgs.overlays = [ forensicsOverlay ];
          nixpkgs.config.allowUnfree = true;
          imports = [
            ./modules/forensics/default.nix
            ./modules/desktop/niri.nix
            ./modules/desktop/xfce.nix
            ./modules/desktop/display-manager.nix
          ];
          hardware.graphics.enable = true;
        };
        default = self.nixosModules.workstation;
      };
    };
}
