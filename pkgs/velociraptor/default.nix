{
  lib,
  stdenv,
  buildGoModule,
  fetchFromGitHub,
  goos ? stdenv.hostPlatform.go.GOOS,
  goarch ? stdenv.hostPlatform.go.GOARCH,
}:

let
  # IMPORTANT: Keep `rev` in sync with `version` (must be the commit SHA of tag `v${version}`)
  # so the `-X ...config.commit_hash` ldflag reports the matching release commit.
  rev = "7d287b0b988b35657e1b401f7b2ffebaf60dbcae";
  isCrossTarget =
    goos != stdenv.buildPlatform.go.GOOS || goarch != stdenv.buildPlatform.go.GOARCH;
  exeSuffix = lib.optionalString (goos == "windows") ".exe";
in
buildGoModule (finalAttrs: {
  pname = "velociraptor" + lib.optionalString isCrossTarget "-${goos}-${goarch}";
  version = "0.77.3";

  src = fetchFromGitHub {
    owner = "Velocidex";
    repo = "velociraptor";
    tag = "v${finalAttrs.version}";
    hash = "sha256-L1OFEgs5QWdu6vh3bDulH+C8wkwR2vBkVQ7l4ojX1T0=";
  };

  vendorHash = "sha256-ebzPsM8Vfw0PPColLy6LjtmmTDVBNTyLc/SX4rYQxBM=";
  proxyVendor = true;

  overrideModAttrs = _: {
    pname = "velociraptor";
    name = "velociraptor-${finalAttrs.version}-go-modules";
    preBuild = "";
    env = { };
  };

  subPackages = [ "bin" ];

  env = {
    CGO_ENABLED = 0;
    GOOS = goos;
    GOARCH = goarch;
  };

  # Mirror upstream magefile.go base_tags + LinuxBare / WindowsBare extra_tags.
  tags = [
    "server_vql"
    "extras"
    "disable_grpc_modules"
    "goexperiment.nojsonv2"
    "release"
    "yara"
    "disable_gui"
  ];

  # Mirror upstream magefile.go ldflags().
  ldflags = [
    "-s"
    "-w"
    "-X www.velocidex.com/golang/velociraptor/config.build_time=1970-01-01T00:00:00Z"
    "-X www.velocidex.com/golang/velociraptor/config.commit_hash=${lib.substring 0 7 rev}"
  ];

  preBuild = ''
    # Generate embedded fileb0x assets (artifacts, config, crypto, gui stub)
    # using the build-host Go environment before compiling ./bin.
    HOME="$TMPDIR" \
    GOOS=${stdenv.buildPlatform.go.GOOS} \
    GOARCH=${stdenv.buildPlatform.go.GOARCH} \
    CGO_ENABLED=0 \
      go run make.go -v basicAssets

    # buildGoModule's configurePhase sets GOOS/GOARCH from stdenv.hostPlatform;
    # override them here for cross-target builds.
    export GOOS=${goos}
    export GOARCH=${goarch}
    export CGO_ENABLED=0
  '';

  # Already stripped via -ldflags="-s -w"; avoid host strip on cross targets.
  dontStrip = true;
  doCheck = false;

  postInstall = ''
    if [ -d "$out/bin/${goos}_${goarch}" ]; then
      mv "$out/bin/${goos}_${goarch}/bin${exeSuffix}" "$out/bin/velociraptor${exeSuffix}"
      rmdir "$out/bin/${goos}_${goarch}"
    elif [ -f "$out/bin/bin${exeSuffix}" ]; then
      mv "$out/bin/bin${exeSuffix}" "$out/bin/velociraptor${exeSuffix}"
    fi
  '';

  meta = {
    description = "Endpoint visibility and digital forensics artifact collection tool (bare CLI build)";
    homepage = "https://github.com/Velocidex/velociraptor";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux ++ lib.platforms.windows;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    mainProgram = "velociraptor${exeSuffix}";
  };
})
