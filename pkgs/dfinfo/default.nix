{ lib, stdenv, makeWrapper, fastfetch, util-linux, iproute2, usbutils, pciutils, dmidecode, gawk, coreutils }:

stdenv.mkDerivation {
  pname = "dfinfo";
  version = "0.1.1";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp dfinfo.sh $out/bin/dfinfo
    chmod +x $out/bin/dfinfo

    wrapProgram $out/bin/dfinfo \
      --prefix PATH : ${lib.makeBinPath [
        fastfetch
        util-linux
        iproute2
        usbutils
        pciutils
        dmidecode
        gawk
        coreutils
      ]}

    # Compatibility symlinks
    ln -s $out/bin/dfinfo $out/bin/dftriage
    ln -s $out/bin/dfinfo $out/bin/df-info
    ln -s $out/bin/dfinfo $out/bin/df-triage
  '';

  meta = with lib; {
    description = "Forensic system triage and fastfetch reporting tool for dfnix";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "dfinfo";
  };
}
