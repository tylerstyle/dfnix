{ lib, stdenv, makeWrapper, kitty, less, coreutils, gnused, bash }:

stdenv.mkDerivation {
  pname = "dfnix-guide";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin $out/share/applications
    cp dfnix-guide.sh $out/bin/dfnix-guide
    chmod +x $out/bin/dfnix-guide

    wrapProgram $out/bin/dfnix-guide \
      --prefix PATH : ${lib.makeBinPath [
        kitty
        less
        coreutils
        gnused
        bash
      ]}

    # Compatibility symlinks
    ln -s $out/bin/dfnix-guide $out/bin/dfguide
    ln -s $out/bin/dfnix-guide $out/bin/df-guide
    ln -s $out/bin/dfnix-guide $out/bin/quickstart

    # Desktop Entry
    cat > $out/share/applications/dfnix-guide.desktop <<EOF
[Desktop Entry]
Version=1.0
Name=dfnix Quick Start Guide
GenericName=Forensic Quick Start & Navigation Guide
Comment=Guide for storage mounting, hardware triage, disk imaging, and Niri navigation
Exec=dfnix-guide
Icon=help-browser
Terminal=false
Type=Application
Categories=System;Documentation;Utility;
Keywords=guide;help;documentation;quickstart;niri;dfdisk;dfmount;dfinfo;forensics;
StartupNotify=true
EOF
  '';

  meta = with lib; {
    description = "Interactive quick start guide and keybinding cheat sheet for dfnix";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "dfnix-guide";
  };
}
