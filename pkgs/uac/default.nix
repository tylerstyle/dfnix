{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  pkgsStatic,
  pkgsCross,
  withBusybox ? false,
}:

let
  staticX86_64 =
    if stdenvNoCC.hostPlatform.isx86_64 then
      pkgsStatic
    else
      pkgsCross.musl64.pkgsStatic;

  staticAarch64 =
    if stdenvNoCC.hostPlatform.isAarch64 then
      pkgsStatic
    else
      pkgsCross.aarch64-multiplatform-musl.pkgsStatic;

  # Safe read-only and file-handling applets from static GNU coreutils (9.11+).
  # Notably, GNU `stat -c "0|%N|%i|%A|%u|%g|%s|%X|%Y|%Z|%W"` invokes Linux
  # `statx(2)` to report file birth time (%W), replacing upstream UAC's
  # prebuilt `statx` blob without losing birth timestamps in bodyfile.yaml.
  # Excludes process/privilege/device mutators (kill, chmod, chown, chroot,
  # mknod, shred, stty, etc.).
  coreutilsApplets = [
    "["
    "arch"
    "b2sum"
    "base32"
    "base64"
    "basename"
    "basenc"
    "cat"
    "cksum"
    "comm"
    "cp"
    "csplit"
    "cut"
    "date"
    "dd"
    "df"
    "dir"
    "dircolors"
    "dirname"
    "du"
    "echo"
    "env"
    "expand"
    "expr"
    "factor"
    "false"
    "fmt"
    "fold"
    "groups"
    "head"
    "hostid"
    "id"
    "join"
    "link"
    "ln"
    "logname"
    "ls"
    "md5sum"
    "mkdir"
    "mkfifo"
    "mktemp"
    "mv"
    "nice"
    "nl"
    "nohup"
    "nproc"
    "numfmt"
    "od"
    "paste"
    "pathchk"
    "pinky"
    "pr"
    "printenv"
    "printf"
    "ptx"
    "pwd"
    "readlink"
    "realpath"
    "rm"
    "rmdir"
    "seq"
    "sha1sum"
    "sha224sum"
    "sha256sum"
    "sha384sum"
    "sha512sum"
    "shuf"
    "sleep"
    "sort"
    "split"
    "stat"
    "sum"
    "sync"
    "tac"
    "tail"
    "tee"
    "test"
    "timeout"
    "touch"
    "tr"
    "true"
    "truncate"
    "tsort"
    "tty"
    "uname"
    "unexpand"
    "uniq"
    "unlink"
    "users"
    "vdir"
    "wc"
    "who"
    "whoami"
    "yes"
  ];

  findutilsBins = [
    "find"
    "xargs"
  ];

  procpsBins = [
    "free"
    "pgrep"
    "pidof"
    "pmap"
    "ps"
    "pwdx"
    "sysctl"
    "top"
    "uptime"
    "vmstat"
  ];

  iproute2Bins = [
    "bridge"
    "ip"
    "lnstat"
    "nstat"
    "rtacct"
    "ss"
    "tc"
  ];

  nettoolsBins = [
    "arp"
    "dnsdomainname"
    "hostname"
    "ifconfig"
    "netstat"
    "route"
  ];

  # Busybox is linked ONLY for archival, compression, and text/stream utilities
  # whose output matches standard tools and never shadows richer system tools:
  # - `stat`, `df`, `ls`, `sha256sum`, `md5sum`, etc. come from static GNU coreutils;
  # - `find` and `xargs` (with `-printf` and `-print0`) come from static GNU findutils;
  # - `ps`, `free`, `sysctl`, `uptime`, etc. come from static procps;
  # - `lsof` comes from static lsof;
  # - `ip`, `ss`, etc. come from static iproute2;
  # - `arp`, `netstat`, `ifconfig`, `route` come from static net-tools;
  # - `rpm`, `dpkg`, `mountpoint`, `dmesg`, `lsmod`, `modinfo`, `lspci`, `lsusb`,
  #   `blkid`, `fuser`, etc. are intentionally NOT linked to busybox so UAC uses
  #   the target system's full utilities instead of stripped busybox stubs.
  busyboxApplets = [
    "awk"
    "bc"
    "bunzip2"
    "bzcat"
    "bzip2"
    "cmp"
    "cpio"
    "dc"
    "diff"
    "dos2unix"
    "egrep"
    "fgrep"
    "grep"
    "gunzip"
    "gzip"
    "hexdump"
    "lzcat"
    "lzma"
    "rev"
    "sed"
    "strings"
    "tar"
    "unix2dos"
    "unlzma"
    "unxz"
    "unzip"
    "uudecode"
    "uuencode"
    "which"
    "xxd"
    "xz"
    "xzcat"
    "zcat"
  ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = if withBusybox then "uac-kit" else "uac";
  version = "3.4.0";

  src = fetchFromGitHub {
    owner = "tclahr";
    repo = "uac";
    rev = "v${finalAttrs.version}";
    hash = "sha256-sFNJeMTGuQ3B3qqCsDRmOsfzBd/P/YEKfKIyjtkuqKI=";
  };

  dontConfigure = true;
  dontBuild = true;
  # Keep portable #!/bin/sh and #!/usr/bin/env perl shebangs so the tree runs
  # on non-NixOS target systems directly from the field-kit USB stick.
  dontPatchShebangs = true;
  dontStrip = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -r uac artifacts bin config lib profiles LICENSE LICENSES.md README.md CHANGELOG.md "$out/"
    chmod +x "$out/uac"

    # Remove upstream's precompiled binary blobs from bin/ so the package is
    # 100% built from source; keep only portable scripts (.sh, .pl) and .txt.
    #
    # Upstream blobs removed and how they are handled:
    # - bin/linux/x86_64/avml: replaced below in both `uac` and `uac-kit` with
    #   source-built static `pkgsStatic.avml` for BOTH x86_64 and arm64.
    # - bin/linux/*/statx: replaced below in both `uac` and `uac-kit` with
    #   source-built static GNU `coreutils` `stat` (which calls Linux `statx(2)`
    #   for `%W` birth time in `lib/setup_tools.sh`:
    #   `stat -c "0|%N|%i|%A|%u|%g|%s|%X|%Y|%Z|%W"`).
    # - bin/{freebsd,netbsd,openbsd,solaris}/*/statf and bin/{esxi,linux,solaris}/*/zip:
    #   optional fallbacks only used when native `stat -f`, `stat.pl` (Perl), or
    #   `tar` are absent on those legacy Unix targets.
    find "$out/bin" -type f ! -name '*.sh' ! -name '*.pl' ! -name '*.txt' -delete
    find "$out/bin" -type d -empty -delete

    install_base_linux_arch() {
      local arch_dir="$1"
      local avml_pkg="$2"
      local cu_pkg="$3"

      mkdir -p "$arch_dir"
      cp "$avml_pkg/bin/avml" "$arch_dir/avml"
      cp "$cu_pkg/bin/coreutils" "$arch_dir/coreutils"
      chmod 0755 "$arch_dir/avml" "$arch_dir/coreutils"
      ln -sf coreutils "$arch_dir/stat"
    }

    install_base_linux_arch "$out/bin/linux/x86_64" "${staticX86_64.avml}" "${staticX86_64.coreutils}"
    install_base_linux_arch "$out/bin/linux/aarch64" "${staticAarch64.avml}" "${staticAarch64.coreutils}"
    # UAC's _get_system_arch_bin_path maps `aarch64*` -> `arm64` when setting PATH.
    ln -s aarch64 "$out/bin/linux/arm64"

    ${lib.optionalString withBusybox ''
      install_kit_linux_arch() {
        local arch_dir="$1"
        local fu_pkg="$2"
        local procps_pkg="$3"
        local lsof_pkg="$4"
        local iproute2_pkg="$5"
        local nettools_pkg="$6"
        local bb_pkg="$7"

        for applet in ${lib.escapeShellArgs coreutilsApplets}; do
          ln -sf coreutils "$arch_dir/$applet"
        done

        for b in ${lib.escapeShellArgs findutilsBins}; do
          cp "$fu_pkg/bin/$b" "$arch_dir/$b"
          chmod 0755 "$arch_dir/$b"
        done

        for b in ${lib.escapeShellArgs procpsBins}; do
          cp "$procps_pkg/bin/$b" "$arch_dir/$b"
          chmod 0755 "$arch_dir/$b"
        done

        cp "$lsof_pkg/bin/lsof" "$arch_dir/lsof"
        chmod 0755 "$arch_dir/lsof"

        for b in ${lib.escapeShellArgs iproute2Bins}; do
          cp "$iproute2_pkg/bin/$b" "$arch_dir/$b"
          chmod 0755 "$arch_dir/$b"
        done

        for b in ${lib.escapeShellArgs nettoolsBins}; do
          cp "$nettools_pkg/bin/$b" "$arch_dir/$b"
          chmod 0755 "$arch_dir/$b"
        done

        cp "$bb_pkg/bin/busybox" "$arch_dir/busybox"
        chmod 0755 "$arch_dir/busybox"
        for applet in ${lib.escapeShellArgs busyboxApplets}; do
          if [ -e "$bb_pkg/bin/$applet" ] || [ -L "$bb_pkg/bin/$applet" ]; then
            ln -sf busybox "$arch_dir/$applet"
          fi
        done
      }

      install_kit_linux_arch \
        "$out/bin/linux/x86_64" \
        "${staticX86_64.findutils}" \
        "${staticX86_64.procps}" \
        "${staticX86_64.lsof}" \
        "${staticX86_64.iproute2}" \
        "${staticX86_64.nettools}" \
        "${staticX86_64.busybox}"

      install_kit_linux_arch \
        "$out/bin/linux/aarch64" \
        "${staticAarch64.findutils}" \
        "${staticAarch64.procps}" \
        "${staticAarch64.lsof}" \
        "${staticAarch64.iproute2}" \
        "${staticAarch64.nettools}" \
        "${staticAarch64.busybox}"
    ''}

    runHook postInstall
  '';

  meta = {
    description =
      "Unix-like Artifact Collector for incident response and live forensics"
      + lib.optionalString withBusybox " (with static Linux triage tools)";
    homepage = "https://github.com/tclahr/uac";
    license =
      with lib.licenses;
      [
        apache2
        mit
        gpl3Plus
      ]
      ++ lib.optionals withBusybox [
        gpl2Only
        gpl2Plus
        lsof
      ];
    platforms = lib.platforms.unix;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
