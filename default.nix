{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:

let
  nixos = import (pkgs.path + "/nixos") {
    configuration = ./configuration.nix;
    system = "x86_64-linux";
  };
in
{
  # Build target for the bootable live ISO:
  # nix-build -A iso
  iso = nixos.config.system.build.isoImage;

  # Fast prototyping VM launcher (skips squashfs compression and ISO packaging):
  # nix-build -A vm -o result-vm
  vm = nixos.config.system.build.vm;

  # Standard packages (ingesting from local sibling repos if available)
  dfdisk = if builtins.pathExists ../dfdisk/package.nix
           then pkgs.callPackage ../dfdisk/package.nix { }
           else pkgs.callPackage ./pkgs/dfdisk { };

  dfmount = if builtins.pathExists ../dfmount/package.nix
            then pkgs.callPackage ../dfmount/package.nix { }
            else pkgs.callPackage ./pkgs/dfmount { };

  dfnet = if builtins.pathExists ../dfnet/package.nix
          then pkgs.callPackage ../dfnet/package.nix { }
          else pkgs.callPackage ./pkgs/dfnet { };

  dfinfo = if builtins.pathExists ../dfinfo/package.nix
           then pkgs.callPackage ../dfinfo/package.nix { }
           else pkgs.callPackage ./pkgs/dfinfo { };

  dwarf2json = pkgs.callPackage ./pkgs/dwarf2json { };
  regripper = pkgs.callPackage ./pkgs/regripper { };

  # Complete system derivation (for testing or persistent install)
  system = nixos.system;
}
