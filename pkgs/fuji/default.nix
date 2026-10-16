{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.2.0";

  dmg = fetchurl {
    url = "https://github.com/Lazza/Fuji/releases/download/${version}/FujiApp-${version}.dmg";
    hash = "sha256-KCSuYrR70+hdoyNNNJYYoFFY2O27WXTi/zKrPJevNzI=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "fuji";
  inherit version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/fuji"
    cp ${dmg} "$out/share/fuji/Fuji.dmg"
    ln -s Fuji.dmg "$out/share/fuji/FujiApp-${version}.dmg"
    ln -s share/fuji/Fuji.dmg "$out/Fuji.dmg"

    runHook postInstall
  '';

  meta = {
    description = "Forensic unattended logical acquisition tool for macOS and recoveryOS (DMG image)";
    homepage = "https://github.com/Lazza/Fuji";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.all;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
