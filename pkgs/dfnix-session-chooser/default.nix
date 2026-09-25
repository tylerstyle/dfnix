{ lib
, python3Packages
, gtk3
, gdk-pixbuf
, librsvg
, wrapGAppsHook3
, gobject-introspection
, mesa-demos
}:

python3Packages.buildPythonApplication {
  pname = "dfnix-session-chooser";
  version = "1.0.0";
  format = "other";

  src = ./.;

  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
  ];

  buildInputs = [
    gtk3
    gdk-pixbuf
    librsvg
  ];

  propagatedBuildInputs = [
    python3Packages.pygobject3
    mesa-demos
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/dfnix/icons

    # Install Python script
    install -m 755 dfnix-session-chooser.py $out/bin/dfnix-session-chooser

    # Install icon assets
    cp -r icons/* $out/share/dfnix/icons/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Forensic Graphical Desktop Session Chooser (Niri Wayland vs XFCE X11)";
    homepage = "https://github.com/tylerstyle/dfnix";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
  };
}
