{ callPackage, ... }@args:

if builtins.pathExists ../../../dfmount/package.nix
then callPackage ../../../dfmount/package.nix (builtins.removeAttrs args [ "callPackage" ])
else
  let
    src = builtins.fetchTarball "https://github.com/tylerstyle/dfmount/archive/main.tar.gz";
  in
  callPackage (src + "/package.nix") (builtins.removeAttrs args [ "callPackage" ])
