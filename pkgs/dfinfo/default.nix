{ lib, stdenv, makeWrapper, fastfetch, util-linux, iproute2, usbutils, pciutils, dmidecode, gawk, coreutils }:

stdenv.mkDerivation {
  pname = "dfinfo";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin $out/share/applications
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

    # Desktop entry
    cat > $out/share/applications/dfinfo.desktop <<EOF
[Desktop Entry]
Version=1.0
Name=dfinfo Forensic Triage
GenericName=Forensic System Triage & Fastfetch
Comment=System hardware triage, fastfetch overview, and concise forensic documentation
Exec=kitty --title "dfinfo - Forensic System Triage" sudo dfinfo
Icon=utilities-system-monitor
Terminal=false
Type=Application
Categories=System;Utility;
Keywords=forensics;triage;fastfetch;system;hardware;evidence;
StartupNotify=true
EOF
  '';

  meta = with lib; {
    description = "Forensic system triage and fastfetch reporting tool for dfnix";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "dfinfo";
  };
}
