# Flakeless entry point (nix-build): evaluates flake.nix through flake-compat, so
# `nix-build -A iso` builds exactly what `nix build .#iso` builds, with every input
# pinned by flake.lock. There is no second, flakeless configuration.
{ ... }:

let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  compat = lock.nodes.flake-compat.locked;
  flake-compat = fetchTarball {
    url = "https://github.com/edolstra/flake-compat/archive/${compat.rev}.tar.gz";
    sha256 = compat.narHash;
  };
  flake = (import flake-compat { src = ./.; }).defaultNix;
  system = "x86_64-linux";
  packages = flake.packages.${system};
in
{
  # nix-build -A iso / vm / vmware / virtualbox
  inherit (packages) iso vm vmware virtualbox;

  # Complete live system closure
  system = flake.nixosConfigurations.df-forensics-iso.config.system.build.toplevel;

  inherit (packages)
    dfcore dfdisk dfmount dfnet dfinfo dfnix-guide dfnix-session-chooser dwarf2json regripper;
}
