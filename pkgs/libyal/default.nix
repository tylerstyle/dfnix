# libyal format libraries and their command-line tools (*info, *mount), built the
# way nixpkgs builds libbde, libewf and libpff, but without the Python bindings.
{ lib, stdenv, fetchurl, pkg-config, fuse3, openssl, zlib }:

let
  mkLibyal = { pname, version, stage, hash, description, dropBins ? [ ] }:
    stdenv.mkDerivation {
      inherit pname version;

      # libyal marks every release a pre-release; "alpha" / "experimental" are
      # part of the tarball name, not a separate development snapshot
      src = fetchurl {
        url = "https://github.com/libyal/${pname}/releases/download/${version}/${pname}-${stage}-${version}.tar.gz";
        inherit hash;
      };

      nativeBuildInputs = [ pkg-config ];
      buildInputs = [ fuse3 openssl zlib ];

      enableParallelBuilding = true;

      # Tools that change the volume they open have no place on a forensic system
      postInstall = lib.concatMapStrings (b: "rm $out/bin/${b}\n") dropBins;

      meta = {
        inherit description;
        homepage = "https://github.com/libyal/${pname}";
        license = lib.licenses.lgpl3Plus;
        platforms = lib.platforms.linux;
      };
    };
in
{
  libvshadow = mkLibyal {
    pname = "libvshadow";
    version = "20260714";
    stage = "alpha";
    hash = "sha256-floET4kAl76MQB2R72EyLDH+OOPB/TrglzF01sdWm9A=";
    description = "Volume Shadow Snapshot (VSS) format: vshadowinfo, vshadowmount";
  };

  libfsapfs = mkLibyal {
    pname = "libfsapfs";
    version = "20260921";
    stage = "experimental";
    hash = "sha256-40Zv+D8M95zoMAcN5QbrVmG9a6JU4UY4PaPPEnnZW1o=";
    description = "Apple File System (APFS), including encrypted volumes: fsapfsinfo, fsapfsmount";
  };

  libfvde = mkLibyal {
    pname = "libfvde";
    version = "20260923";
    stage = "experimental";
    hash = "sha256-bXVb7t9QB155nXwbltA3ukCGulLCL6SvSFyJ2PZrHos=";
    description = "FileVault Drive Encryption (FVDE, Core Storage): fvdeinfo, fvdemount";
    # fvdewipekey erases the volume's encrypted key material
    dropBins = [ "fvdewipekey" ];
  };
}
