{ pkgs }:

let
  inherit (pkgs) lib runCommand python3;

  # Base utilities providing standard system binaries (matching /run/current-system/sw/bin on the ISO)
  # to prevent false positives on shell scripts relying on core POSIX utilities.
  baseUtils = [
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnused
    pkgs.gnugrep
    pkgs.gawk
    pkgs.bash
    pkgs.which
    pkgs.util-linux
    pkgs.perl
  ];

  smokeBasePath = lib.makeBinPath baseUtils;

  forensicsMod = import ../../modules/forensics/default.nix {
    config = { dfnix.forensics.enable = true; };
    lib = pkgs.lib;
    inherit pkgs;
  };
  forensicsPackages = forensicsMod.config.content.environment.systemPackages;

  # Build JSON list of { "pname": "<pname>", "path": "<outPath>" }.
  # String context is preserved so Nix builds/fetches the complete closure of all forensic packages.
  pkgsList = map (p: {
    pname = lib.getName p;
    path = "${p}";
  }) forensicsPackages;

  pkgsJson = pkgs.writeText "forensic-packages.json" (builtins.toJSON pkgsList);
  checkerScript = ./check-tools.py;
in
runCommand "check-tool-smoke"
  {
    nativeBuildInputs = [ python3 ];
    SMOKE_BASE_PATH = smokeBasePath;
  }
  ''
    python3 ${checkerScript} --pkgs "${pkgsJson}" --out "$out"
  ''
