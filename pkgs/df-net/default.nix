{ lib, stdenv, makeWrapper, macchanger, networkmanager, arp-scan, cifs-utils, nfs-utils, netcat, pv, iproute2, gawk }:

stdenv.mkDerivation {
  pname = "df-net";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp df-net.sh $out/bin/df-net
    chmod +x $out/bin/df-net

    wrapProgram $out/bin/df-net \
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
  '';

  meta = with lib; {
    description = "Forensic network acquisition and triage helper for df-nix";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
