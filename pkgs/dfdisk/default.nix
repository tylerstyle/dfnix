{ lib
, rustPlatform
, fetchFromGitHub
, makeWrapper
, pkg-config
, libewf
, smartmontools
, ddrescue
, util-linux
, systemd
}:

rustPlatform.buildRustPackage rec {
  pname = "dfdisk";
  version = "0.1.5";

  src = fetchFromGitHub {
    owner = "tylerstyle";
    repo = "dfdisk";
    tag = "v${version}";
    hash = "sha256-ZMrXRxsX9Ms49EZoesKoAslI6bPxL8AFz4tGVtK8VwQ=";
  };

  cargoHash = "sha256-xVfUMFseLgX7CCE3kk2JLrLvflRiYZTe/B2TcBxZHGk=";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    util-linux
  ];

  buildInputs = [
    libewf
    smartmontools
    ddrescue
    util-linux
    systemd
  ];

  postInstall = ''
    wrapProgram $out/bin/dfdisk \
      --prefix PATH : ${lib.makeBinPath [
        libewf
        smartmontools
        ddrescue
        util-linux
        systemd
      ]}
  '';

  meta = with lib; {
    description = "Modern forensic disk imaging, damaged media rescue and conversion CLI/TUI tool";
    homepage = "https://github.com/tylerstyle/dfdisk";
    license = with licenses; [ mit asl20 ];
    maintainers = [ ];
    mainProgram = "dfdisk";
    platforms = platforms.linux;
  };
}
