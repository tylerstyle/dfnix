{ lib, stdenv, makeWrapper, macchanger, networkmanager, arp-scan, cifs-utils, nfs-utils, netcat, pv, iproute2, gawk }:

stdenv.mkDerivation {
  pname = "dfnet";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin $out/share/applications
    cp dfnet.sh $out/bin/dfnet
    chmod +x $out/bin/dfnet

    wrapProgram $out/bin/dfnet \
      --prefix PATH : ${lib.makeBinPath [
        macchanger
        networkmanager
        arp-scan
        cifs-utils
        nfs-utils
        netcat
        pv
        iproute2
        gawk
      ]}

    # Compatibility symlink
    ln -s $out/bin/dfnet $out/bin/df-net

    # Desktop entry
    cat > $out/share/applications/dfnet.desktop <<EOF
[Desktop Entry]
Version=1.0
Name=dfnet Network Triage
GenericName=Forensic Network Operations
Comment=MAC spoofing, static IP setup (nmtui), network share mounting, and raw disk reception
Exec=kitty --title "dfnet - Forensic Network Operations" -e sudo dfnet
Icon=network-workgroup
Terminal=false
Type=Application
Categories=System;Network;Forensics;Utility;
Keywords=forensics;network;macchanger;nmtui;smb;nfs;
StartupNotify=true
EOF
  '';

  meta = with lib; {
    description = "Forensic network acquisition and triage helper for df-nix";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "dfnet";
  };
}
