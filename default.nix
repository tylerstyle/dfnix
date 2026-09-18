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

  # Standard packages
  dfdisk = pkgs.callPackage ./pkgs/dfdisk { };
  df-mount = pkgs.callPackage ./pkgs/df-mount { };
  df-net = pkgs.callPackage ./pkgs/df-net { };
  dwarf2json = pkgs.callPackage ./pkgs/dwarf2json { };
  regripper = pkgs.callPackage ./pkgs/regripper { };

  # Complete system derivation (for testing or persistent install)
  system = nixos.system;
}
