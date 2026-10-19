{ pkgs ? nixosConfig.pkgs, nixosConfig }:

let
  inherit (pkgs) lib runCommand python3 linkFarm;
  sysPkgs = nixosConfig.pkgs;
  config = nixosConfig.config;

  # Filter all .desktop item derivations installed in environment.systemPackages.
  # These are lightweight text derivations (makeDesktopItem) that create share/applications/*.desktop.
  desktopItemPackages = builtins.filter (
    p: lib.hasSuffix ".desktop" (p.name or "")
  ) config.environment.systemPackages;

  # Build a linkFarm directory containing all installed desktop item derivations.
  # The checker script scans share/applications/*.desktop inside this directory.
  desktopItemsDir = linkFarm "installed-desktop-items" (
    map (p: { name = p.name; path = p; }) desktopItemPackages
  );

  # Providers mapping: command name or desktop ID -> package derivation OR string (package name)
  providers = {
    # Desktop executables / commands
    "dfdisk" = sysPkgs.dfdisk;
    "dfmount" = sysPkgs.dfmount;
    "dfnet" = sysPkgs.dfnet;
    "dfcollect" = sysPkgs.dfcollect;
    "dfinfo" = sysPkgs.dfinfo;
    "dfkit" = sysPkgs.dfkit;
    "dfkit-shell" = "dfkit-shell";
    "dfnix-guide" = sysPkgs.dfnix-guide;
    "kitty" = sysPkgs.kitty;
    "dolphin" = sysPkgs.kdePackages.dolphin;
    "firefox" = sysPkgs.firefox;
    "noctalia" = sysPkgs.noctalia;
    "swaybg" = sysPkgs.swaybg;
    "xhost" = sysPkgs.xhost;
    "lsblk" = sysPkgs.util-linux;
    "xways" = "xways";
    "guymager-root" = "guymager-root";
    "xwayland-satellite" = sysPkgs.xwayland-satellite;

    # Pinned desktop items that ship inside regular packages:
    "dfnix-guide.desktop" = sysPkgs.dfnix-guide;
    "kitty.desktop" = sysPkgs.kitty;
    "dolphin.desktop" = sysPkgs.kdePackages.dolphin;

    # Pinned desktop items that are makeDesktopItem derivations (string matches p.name):
    "dfdisk.desktop" = "dfdisk.desktop";
    "dfmount.desktop" = "dfmount.desktop";
    "dfnet.desktop" = "dfnet.desktop";
    "dfcollect.desktop" = "dfcollect.desktop";
    "dfinfo.desktop" = "dfinfo.desktop";
    "dfkit.desktop" = "dfkit.desktop";
    "xways.desktop" = "xways.desktop";
    "guymager.desktop" = "guymager.desktop";
  };

  # Discard string context so packages are NOT added to the derivation's closure inputs
  installedOutPaths = map (x: builtins.unsafeDiscardStringContext x.outPath) config.environment.systemPackages;
  installedNames = map (x: x.name) config.environment.systemPackages;
  installedBaseNames = map (x: lib.getName x) config.environment.systemPackages;

  providersStatus = lib.mapAttrs (name: provider:
    if provider == null then
      false
    else if builtins.isString provider then
      builtins.elem provider installedNames || builtins.elem provider installedBaseNames
    else
      builtins.elem (builtins.unsafeDiscardStringContext provider.outPath) installedOutPaths
  ) providers;

  providersJson = builtins.toFile "providers.json" (builtins.toJSON providersStatus);

  checkerScript = ./check-desktop-commands.py;
  configToml = ../../configs/noctalia/config.toml;
  configKdl = ../../configs/niri/config.kdl;
  noctaliaKdl = ../../configs/niri/noctalia.kdl;
in
runCommand "check-desktop-commands"
  {
    nativeBuildInputs = [ python3 sysPkgs.niri ];
  }
  ''
    echo "==> Validating Niri configuration..."
    mkdir -p niri-cfg
    cp "${configKdl}" niri-cfg/config.kdl
    cp "${noctaliaKdl}" niri-cfg/noctalia.kdl
    niri validate -c niri-cfg/config.kdl

    echo "==> Validating desktop commands..."
    python3 ${checkerScript} \
      --providers "${providersJson}" \
      --toml "${configToml}" \
      --kdl "${configKdl}" \
      --desktop-dir "${desktopItemsDir}"

    mkdir -p $out
    echo "ok" > $out/success
  ''
