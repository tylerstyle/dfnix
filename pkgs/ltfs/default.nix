# LTFS (Linear Tape File System): the reference implementation for stand-alone
# LTO tape drives. Mounts an LTFS-formatted tape as a file system (FUSE) and
# brings ltfsck and mkltfs. nixpkgs has no LTFS package.
#
# Evidence tapes: the block-device write blocking of dfnix does not cover tape
# drives. Set the cartridge's write-protect tab and mount with `-o ro`; a
# read-write mount writes a new index to the tape when it is unmounted.
{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
  fetchurl,
  libxml2,
  icu,
  net-snmp,
  libuuid,
  python3,
}:

let
  # LTFS uses the FUSE 2 API (upstream's FUSE 3 port is an open pull request).
  # nixpkgs dropped libfuse 2, so the last release is built here, as a library
  # for ltfs only: no setuid fusermount, ltfs mounts as root.
  libfuse2 = stdenv.mkDerivation rec {
    pname = "libfuse";
    version = "2.9.9";

    src = fetchurl {
      url = "https://github.com/libfuse/libfuse/releases/download/fuse-${version}/fuse-${version}.tar.gz";
      hash = "sha256-0OadXWCMwi/0hDeRrQl/VU3TJUDdyb7XY4zG/qfBtLU=";
    };

    # glibc 2.34 and later have closefrom() themselves
    postPatch = ''
      sed -i 's/^static void closefrom(int minfd)/static void fuse_closefrom(int minfd)/; s/\bclosefrom(3);/fuse_closefrom(3);/' util/ulockmgr_server.c
    '';

    configureFlags = [
      "--disable-example"
      "--disable-util"
      "--enable-lib"
    ];

    enableParallelBuilding = true;

    meta.license = with lib.licenses; [ gpl2Only lgpl21Only ];
  };
in
stdenv.mkDerivation rec {
  pname = "ltfs";
  version = "2.4.9.1-10524";

  src = fetchFromGitHub {
    owner = "LinearTapeFileSystem";
    repo = "ltfs";
    rev = "v${version}";
    fetchSubmodules = true; # uthash
    hash = "sha256-VMKIc7I0w7+8YyKil0RkzjXK8mzim/VDIPuBd/SQlZ8=";
  };

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    icu # genrb, pkgdata for the message bundles
    net-snmp # net-snmp-config
  ];

  buildInputs = [
    libfuse2
    libxml2
    icu
    net-snmp
    libuuid
    # ltfs_ordered_copy (copies in the order the files lie on tape)
    (python3.withPackages (ps: [ ps.pyxattr ]))
  ];

  # The bundled uthash declares variables in the middle of blocks, which the
  # project's own flags turn into an error
  env.NIX_CFLAGS_COMPILE = "-Wno-error=declaration-after-statement";

  enableParallelBuilding = true;

  meta = {
    description = "Reference implementation of the Linear Tape File System for stand-alone LTO drives";
    homepage = "https://github.com/LinearTapeFileSystem/ltfs";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    mainProgram = "ltfs";
  };
}
