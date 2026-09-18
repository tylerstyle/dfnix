{ lib, stdenv, fetchFromGitHub, perl, makeWrapper, perlPackages }:

stdenv.mkDerivation rec {
  pname = "regripper";
  version = "3.0";

  src = fetchFromGitHub {
    owner = "keydet89";
    repo = "RegRipper3.0";
    rev = "master";
    hash = "sha256-W3U0Y99d8nB8Q7/f8pQp0Zf6P5Z7q9Q6B7o9E0s1K3A=";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [
    perl
    perlPackages.ParseWin32Registry
  ];

  postPatch = ''
    substituteInPlace rip.pl \
      --replace-fail 'my $plugindir;' "my \$plugindir = \"$out/share/regripper/plugins/\";"
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/regripper/plugins
    cp -r plugins/* $out/share/regripper/plugins/
    cp rip.pl $out/bin/rip.pl
    chmod +x $out/bin/rip.pl

    wrapProgram $out/bin/rip.pl \
      --set PERL5LIB "${perlPackages.makePerlPath [ perlPackages.ParseWin32Registry ]}:$out/share/regripper"

    ln -s $out/bin/rip.pl $out/bin/regripper

    runHook postInstall
  '';

  meta = with lib; {
    description = "Fast, extensible tool for extracting artifacts from Windows Registry hives";
    homepage = "https://github.com/keydet89/RegRipper3.0";
    license = licenses.gpl3Only;
    mainProgram = "regripper";
  };
}
