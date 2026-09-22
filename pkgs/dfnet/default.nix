{ callPackage, ... }@args:

if builtins.pathExists ../../../dfnet/package.nix
then callPackage ../../../dfnet/package.nix (builtins.removeAttrs args [ "callPackage" ])
else
  let
    src = builtins.fetchTarball "https://github.com/tylerstyle/dfnet/archive/main.tar.gz";
  in
  callPackage (src + "/package.nix") (builtins.removeAttrs args [ "callPackage" ])
