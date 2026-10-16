{
  description = "dfnix: Live Bootable NixOS Distribution Tuned for Forensic Field Work";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Lets default.nix evaluate this flake for flakeless (nix-build) users
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    # Shared forensic safety core (device topology, protected-device registry,
    # audit log). The tools build against this same source.
    dfcore = {
      url = "github:tylerstyle/dfcore";
      flake = false;
    };

    # Forensic Disk Imager by Tylerstyle
    dfdisk = {
      url = "github:tylerstyle/dfdisk";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dfcore.follows = "dfcore";
    };

    # Dedicated Forensic Storage Mounter by Tylerstyle
    dfmount = {
      url = "github:tylerstyle/dfmount";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dfcore.follows = "dfcore";
    };

    # Dedicated Forensic Network Operations by Tylerstyle
    dfnet = {
      url = "github:tylerstyle/dfnet";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dfcore.follows = "dfcore";
    };
  };

  outputs = { self, nixpkgs, dfcore, dfdisk, dfmount, dfnet, ... }@inputs:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Git revision stamped into /etc/dfnix-release and every audit record. Nix
      # withholds it while an input is missing from flake.lock (supplied only by
      # --override-input), which marks a development build, not a release.
      revision = self.rev or self.dirtyRev or "unlocked-inputs";

      # Custom packages overlay
      forensicsOverlay = final: prev: {
        # Upstream forensic tools from flake inputs
        dfdisk = dfdisk.packages.${prev.stdenv.hostPlatform.system}.default;
        dfmount = dfmount.packages.${prev.stdenv.hostPlatform.system}.default;
        dfnet = dfnet.packages.${prev.stdenv.hostPlatform.system}.default;

        # Protected-device registry and audit log tools (dfcore-protect, dfcore-audit)
        dfcore = final.callPackage "${dfcore}/package.nix" { };

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

        # Field-kit third-party packages (for the multi-OS field-kit USB stick)
        uac = final.callPackage ./pkgs/uac { };
        uac-kit = final.callPackage ./pkgs/uac {
          withBusybox = true;
        };
        velociraptor = final.callPackage ./pkgs/velociraptor { };
        velociraptor-linux-amd64 = final.callPackage ./pkgs/velociraptor {
          goos = "linux";
          goarch = "amd64";
        };
        velociraptor-linux-arm64 = final.callPackage ./pkgs/velociraptor {
          goos = "linux";
          goarch = "arm64";
        };
        velociraptor-windows-amd64 = final.callPackage ./pkgs/velociraptor {
          goos = "windows";
          goarch = "amd64";
        };
        velociraptor-windows-arm64 = final.callPackage ./pkgs/velociraptor {
          goos = "windows";
          goarch = "arm64";
        };
        winpmem = final.callPackage ./pkgs/winpmem { };
        fuji = final.callPackage ./pkgs/fuji { };
        fieldkit = final.callPackage ./pkgs/fieldkit { };
      };

      # Everything a dfnix system needs from this flake besides its profile
      flakeModule = {
        nixpkgs.overlays = [ forensicsOverlay ];
        dfnix.release.revision = revision;
      };

      mkSystem = profile: extra: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [ flakeModule profile ] ++ extra;
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
          inherit (pkgs)
            dfcore
            dfdisk
            dfmount
            dfnet
            dfinfo
            dfnix-guide
            dwarf2json
            regripper
            dfnix-session-chooser
            uac
            uac-kit
            velociraptor
            velociraptor-linux-amd64
            velociraptor-linux-arm64
            velociraptor-windows-amd64
            velociraptor-windows-arm64
            winpmem
            fuji
            fieldkit
            ;

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

      # CFTT-style write-blocking regression test & fieldkit image verification
      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ forensicsOverlay ];
            config.allowUnfree = true;
          };
        in
        {
          cftt = import ./tests/cftt { inherit pkgs; };
          fieldkit = import ./tests/fieldkit { inherit pkgs; };
        }
      );

      # NixOS System Configurations (see profiles/)
      nixosConfigurations = {
        # Bootable live forensic ISO: nix build .#iso
        df-forensics-iso = mkSystem ./profiles/live.nix [ ];

        # VMware Workstation / Fusion / ESXi appliance (.vmdk): nix build .#vmware
        df-forensics-vmware = mkSystem ./profiles/appliance-vmware.nix [ ];

        # VirtualBox appliance (.ova): nix build .#virtualbox
        df-forensics-vbox = mkSystem ./profiles/appliance-virtualbox.nix [ ];

        # Persistent lab workstation (standalone test configuration)
        df-forensics-workstation = mkSystem ./profiles/workstation.nix [
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

      # Export reusable NixOS modules for persistent installations
      nixosModules = {
        forensics = ./modules/forensics/default.nix;
        writeBlocking = ./modules/hardware/write-blocking.nix;
        protectedDevices = ./modules/hardware/protected-devices.nix;
        release = ./modules/release.nix;
        niri = ./modules/desktop/niri.nix;
        xfce = ./modules/desktop/xfce.nix;
        displayManager = ./modules/desktop/display-manager.nix;
        liveIso = ./modules/iso/live-iso.nix;
        wineXways = ./modules/forensics/wine-xways.nix;
        desktopEntries = ./modules/desktop/entries.nix;
        commonGui = ./modules/desktop/common-gui.nix;

        # Lab workstation profile with the dfnix overlay, for persistent installations
        workstation = { lib, ... }: {
          imports = [ ./profiles/workstation.nix ];
          nixpkgs.overlays = [ forensicsOverlay ];
          dfnix.release.revision = lib.mkDefault revision;
        };
        default = self.nixosModules.workstation;
      };
    };
}
