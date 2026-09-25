{
  description = "dfnix: Live Bootable NixOS Distribution Tuned for Forensic Field Work";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Forensic Disk Imager by Tylerstyle
    dfdisk = {
      url = "github:tylerstyle/dfdisk";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Dedicated Forensic Storage Mounter by Tylerstyle
    dfmount = {
      url = "github:tylerstyle/dfmount";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Dedicated Forensic Network Operations by Tylerstyle
    dfnet = {
      url = "github:tylerstyle/dfnet";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, dfdisk, dfmount, dfnet, ... }@inputs:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Custom packages overlay
      forensicsOverlay = final: prev: {
        # Upstream forensic tools from flake inputs
        dfdisk = dfdisk.packages.${prev.stdenv.hostPlatform.system}.default;
        dfmount = dfmount.packages.${prev.stdenv.hostPlatform.system}.default;
        dfnet = dfnet.packages.${prev.stdenv.hostPlatform.system}.default;

        # Forensic System Triage & Fastfetch Reporter
        dfinfo = final.callPackage ./pkgs/dfinfo { };

        # Forensic Quick Start & Navigation Guide
        dfnix-guide = final.callPackage ./pkgs/dfnix-guide { };

        # Forensic Graphical Desktop Session Chooser
        dfnix-session-chooser = final.callPackage ./pkgs/dfnix-session-chooser { };

        # Volatility 3 ISF generator
        dwarf2json = final.callPackage ./pkgs/dwarf2json { };

        # Windows Registry parser
        regripper = final.callPackage ./pkgs/regripper { };
      };

      # Common desktop entries for forensic tools
      desktopEntriesModule = { pkgs, ... }: {
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
      };

      # Common GUI, fonts, and terminal settings
      commonGuiModule = { pkgs, ... }: {
        hardware.graphics = {
          enable = true;
          enable32Bit = true;
        };

        services.xserver.xkb = {
          layout = "de,us";
          options = "grp:alt_shift_toggle";
        };

        fonts.packages = with pkgs; [
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji
          nerd-fonts.fira-code
          nerd-fonts.symbols-only
        ];

        environment.systemPackages = with pkgs; [
          firefox
          chromium
        ];

        programs.starship = {
          enable = true;
          presets = [ ];
        };
        programs.bash.completion.enable = true;
      };
    in
    {
      # Export custom packages overlay
      overlays.default = forensicsOverlay;

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
          inherit (pkgs) dfdisk dfmount dfnet dfinfo dfnix-guide dwarf2json regripper dfnix-session-chooser;
          
          # Shortcut: nix build .#iso
          iso = self.nixosConfigurations.df-forensics-iso.config.system.build.isoImage;

          # Fast prototyping VM shortcut: nix build .#vm
          vm = self.nixosConfigurations.df-forensics-iso.config.system.build.vm;

          # VMware appliance image (.vmdk): nix build .#vmware
          vmware = self.nixosConfigurations.df-forensics-vmware.config.system.build.vmwareImage;

          # VirtualBox appliance image (.ova): nix build .#virtualbox
          virtualbox = self.nixosConfigurations.df-forensics-vbox.config.system.build.virtualBoxOVA;
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
            desktopEntriesModule
            commonGuiModule

            # Rapid Prototyping VM resources (applied when building system.build.vm)
            ({ pkgs, ... }: {
              virtualisation.vmVariant = {
                virtualisation.memorySize = 8192; # 8 GiB RAM
                virtualisation.cores = 4;         # 4 CPU cores
                virtualisation.efi.OVMF = pkgs.OVMF // { systemManagementModeRequired = false; };
                boot.kernelParams = nixpkgs.lib.mkVMOverride [ "panic=10" ]; # Skip copytoram in VM closure
                boot.initrd.systemd.services.copytoram.enable = false;
              };
            })
          ];
        };

        # Target 2: VMware Workstation / Fusion / ESXi Appliance (.vmdk)
        # Build command: nix build .#nixosConfigurations.df-forensics-vmware.config.system.build.vmwareImage
        df-forensics-vmware = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/vmware-image.nix"

            {
              nixpkgs.overlays = [ forensicsOverlay ];
              nixpkgs.config.allowUnfree = true;
            }

            ./modules/hardware/write-blocking.nix
            ./modules/forensics/default.nix
            ./modules/forensics/wine-xways.nix
            ./modules/desktop/niri.nix
            ./modules/desktop/xfce.nix
            ./modules/desktop/display-manager.nix
            desktopEntriesModule
            commonGuiModule

            ({ pkgs, lib, ... }: {
              # VM appliances present graphical chooser at boot to select Niri or XFCE
              dfnix.desktop.displayManager.enable = true;
              dfnix.desktop.displayManager.defaultDesktop = "chooser";
              dfnix.desktop.displayManager.autologin = true;
              dfnix.desktop.displayManager.autologinUser = "nixos";

              # Enforce write-blocking by default on attached evidence drives, exempting only appliance OS disk (sda and partitions)
              dfnix.writeBlocking.enable = true;
              dfnix.writeBlocking.readOnlyAll = true;
              dfnix.writeBlocking.exemptDevices = [ "sda" "sda[0-9]*" ];

              # Sizable VMDK capacity for forensic analysis & triage staging
              virtualisation.diskSize = 30720; # 30 GiB (sparse VMDK)

              # Examiner user account
              users.users.nixos = {
                isNormalUser = true;
                extraGroups = [ "wheel" "disk" "storage" "networkmanager" "video" "audio" "input" ];
                description = "Forensic Field Examiner";
                initialHashedPassword = "";
              };
              users.users.root.initialHashedPassword = "";
              security.sudo.wheelNeedsPassword = false;

              # Air-gap network defaults with NetworkManager
              networking.hostName = "df-vmware";
              networking.networkmanager.enable = true;
              systemd.services.NetworkManager-wait-online.enable = false;

              # Timezone & Localization
              time.timeZone = "Europe/Berlin";
              i18n.defaultLocale = "en_US.UTF-8";
              console.keyMap = "de";

              system.stateVersion = "24.11";
            })
          ];
        };

        # Target 3: VirtualBox Appliance (.ova)
        # Build command: nix build .#nixosConfigurations.df-forensics-vbox.config.system.build.virtualBoxOVA
        df-forensics-vbox = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/virtualbox-image.nix"

            {
              nixpkgs.overlays = [ forensicsOverlay ];
              nixpkgs.config.allowUnfree = true;
            }

            ./modules/hardware/write-blocking.nix
            ./modules/forensics/default.nix
            ./modules/forensics/wine-xways.nix
            ./modules/desktop/niri.nix
            ./modules/desktop/xfce.nix
            ./modules/desktop/display-manager.nix
            desktopEntriesModule
            commonGuiModule

            ({ pkgs, lib, ... }: {
              # VM appliances present graphical chooser at boot to select Niri or XFCE
              dfnix.desktop.displayManager.enable = true;
              dfnix.desktop.displayManager.defaultDesktop = "chooser";
              dfnix.desktop.displayManager.autologin = true;
              dfnix.desktop.displayManager.autologinUser = "nixos";

              # Enforce write-blocking by default on attached evidence drives, exempting only appliance OS disk (sda and partitions)
              dfnix.writeBlocking.enable = true;
              dfnix.writeBlocking.readOnlyAll = true;
              dfnix.writeBlocking.exemptDevices = [ "sda" "sda[0-9]*" ];

              # Forensic safety: Inhibit swap file on disk
              swapDevices = lib.mkForce [ ];

              # Resource sizing for forensic workloads
              virtualbox.memorySize = 8192; # 8 GiB RAM
              virtualbox.params.cpus = 4;   # 4 vCPUs
              virtualisation.diskSize = 30720; # 30 GiB

              # Forensic guest isolation defaults
              virtualisation.virtualbox.guest = {
                clipboard = false;
                dragAndDrop = false;
                seamless = false;
                vboxsf = false;
              };

              # Examiner user account
              users.users.nixos = {
                isNormalUser = true;
                extraGroups = [ "wheel" "disk" "storage" "networkmanager" "video" "audio" "input" ];
                description = "Forensic Field Examiner";
                initialHashedPassword = "";
              };
              users.users.root.initialHashedPassword = "";
              security.sudo.wheelNeedsPassword = false;

              # Air-gap network defaults with NetworkManager
              networking.hostName = "df-vbox";
              networking.networkmanager.enable = true;
              systemd.services.NetworkManager-wait-online.enable = false;

              # Timezone & Localization
              time.timeZone = "Europe/Berlin";
              i18n.defaultLocale = "en_US.UTF-8";
              console.keyMap = "de";

              system.stateVersion = "24.11";
            })
          ];
        };

        # Target 4: Persistent Lab Workstation Profile (Standalone test configuration)
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
        desktopEntries = desktopEntriesModule;
        commonGui = commonGuiModule;

        workstation = { pkgs, lib, ... }: {
          nixpkgs.overlays = [ forensicsOverlay ];
          nixpkgs.config.allowUnfree = true;
          imports = [
            ./modules/hardware/write-blocking.nix
            ./modules/forensics/default.nix
            ./modules/forensics/wine-xways.nix
            ./modules/desktop/niri.nix
            ./modules/desktop/xfce.nix
            ./modules/desktop/display-manager.nix
            desktopEntriesModule
            commonGuiModule
          ];
          # Physical workstation defaults:
          # Enable forensic storage invariants (swap masking, RAID/LVM lockdown, GPT auto-discovery disable)
          # while keeping OS root disk writable:
          dfnix.writeBlocking.enable = lib.mkDefault true;
          dfnix.writeBlocking.readOnlyAll = lib.mkDefault false;
          # Display manager autologin disabled by default to preserve standard user login
          dfnix.desktop.displayManager.autologin = lib.mkDefault false;
        };
        default = self.nixosModules.workstation;
      };
    };
}
