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
  version = "0.1.6";

  src = fetchFromGitHub {
    owner = "tylerstyle";
    repo = "dfdisk";
    tag = "v${version}";
    hash = "sha256-XgqD315uKf/Pi1FNrTM/jmGNPEK6uUCQvXOMaoF/0vM=";
  };

  cargoHash = "sha256-86F8p+RLsgryON5JxfCrezP1VY3JzK+w6cm+3orgxZM=";

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
