{ lib
, stdenv
, makeWrapper
, util-linux
, gawk
, gnugrep
, coreutils
, python3
, wrapGAppsHook4
, gtk4
, libadwaita
, gobject-introspection
}:

let
  pythonEnv = python3.withPackages (ps: with ps; [
    pygobject3
  ]);
in
stdenv.mkDerivation rec {
  pname = "df-mount";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    makeWrapper
    wrapGAppsHook4
    gobject-introspection
  ];

  buildInputs = [
    gtk4
    libadwaita
    pythonEnv
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/applications

    # Install CLI wrapper
    cp df-mount.sh $out/bin/df-mount
    chmod +x $out/bin/df-mount

    wrapProgram $out/bin/df-mount \
      --prefix PATH : ${lib.makeBinPath [
        util-linux
        gawk
        gnugrep
        coreutils
      ]}

    # Helper symlinks
    ln -s $out/bin/df-mount $out/bin/df-status
    ln -s $out/bin/df-mount $out/bin/df-unblock
    ln -s $out/bin/df-mount $out/bin/df-target
    ln -s $out/bin/df-mount $out/bin/df-umount

    # Install GUI wrapper
    cp df-mount-gui.py $out/bin/df-mount-gui
    chmod +x $out/bin/df-mount-gui

    wrapProgram $out/bin/df-mount-gui \
      --prefix PATH : ${lib.makeBinPath [
        util-linux
        gawk
        gnugrep
        coreutils
      ]}:$out/bin \
      --prefix PYTHONPATH : "${pythonEnv}/${pythonEnv.sitePackages}"

    # Desktop entry for GUI
    cat > $out/share/applications/df-mount-gui.desktop <<EOF
[Desktop Entry]
Version=1.0
Name=df-mount Forensic Manager
GenericName=Forensic Disk Mounter
Comment=Mount evidence write-blocked with zero journal replay or unblock target drives
Exec=sudo df-mount-gui
Icon=drive-harddisk-system
Terminal=false
Type=Application
Categories=System;Forensics;Utility;
Keywords=forensics;mount;writeblock;target;dfdisk;
EOF

    runHook postInstall
  '';

  meta = with lib; {
    description = "Forensic disk mounting & target management suite for df-nix";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
