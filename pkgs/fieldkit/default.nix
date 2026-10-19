{
  lib,
  stdenvNoCC,
  runCommand,
  vmTools,
  writeText,
  python3,
  gptfdisk,
  util-linux,
  hfsprogs,
  e2fsprogs,
  exfatprogs,
  attr,
  kmod,
  pkgsStatic,
  pkgsCross,
  uac,
  uac-kit,
  velociraptor,
  velociraptor-linux-amd64,
  velociraptor-linux-arm64,
  velociraptor-windows-amd64,
  velociraptor-windows-arm64,
  winpmem,
  fuji,
  dflive-static,
  dflive-aarch64-static,
  dflive-windows,
  dflive-source,
}:

let
  version = "0.2.0";

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

  playbookWin = ../../docs/playbooks/live-windows.md;
  playbookMac = ../../docs/playbooks/live-macos.md;
  playbookLnx = ../../docs/playbooks/live-linux.md;

  # Pinned Velociraptor offline collector specification for KIT-WIN.
  # Can be invoked directly with:
  #   velociraptor-windows-amd64.exe --config collector-spec.yaml artifacts collect DFNIX.Windows.Triage --require_admin --nobanner --output F:\velo_%COMPUTERNAME%.zip
  # Or embedded into a zero-argument collector binary via `velociraptor config repack` (see REPACK.md).
  velociraptorCollectorSpec = ./collector-spec.yaml;

  velociraptorRepackMd = writeText "REPACK.md" ''
    # Velociraptor Offline Collector Usage & Repack Instructions

    `KIT-WIN` ships the bare Windows Velociraptor binaries built from source
    (`velociraptor-windows-amd64.exe` and `velociraptor-windows-arm64.exe`)
    alongside `collector-spec.yaml` (`DFNIX.Windows.Triage`).

    ## 1. Direct execution from `KIT-WIN` (recommended)

    Run directly from an elevated Command Prompt (`cmd.exe` as Administrator),
    writing the output ZIP container and temporary files to an external target
    drive (`F:\`) or `KIT-OUT` (`E:\`):

    ```bat
    mkdir F:\temp
    D:\velociraptor\velociraptor-windows-amd64.exe --config D:\velociraptor\collector-spec.yaml artifacts collect DFNIX.Windows.Triage --require_admin --nobanner --tempdir F:\temp --output F:\velo_%COMPUTERNAME%.zip
    ```

    On Windows on Arm (`arm64`), use `velociraptor-windows-arm64.exe`.

    ## 2. Repacking a zero-argument self-contained collector (`config repack`)

    If you need a single self-contained `.exe` that runs `autoexec` automatically
    when launched without command-line arguments:

    ### On `dfnix` (before going on scene)

    ```sh
    velociraptor config repack \
      --exe /mnt/kit-win/velociraptor/velociraptor-windows-amd64.exe \
      /mnt/kit-win/velociraptor/collector-spec.yaml \
      /mnt/target/velociraptor-collector-amd64.exe
    ```

    ### On Windows

    ```bat
    D:\velociraptor\velociraptor-windows-amd64.exe config repack --exe D:\velociraptor\velociraptor-windows-amd64.exe D:\velociraptor\collector-spec.yaml E:\velociraptor-collector-amd64.exe
    ```

    Inspect the embedded configuration of any repacked binary with:

    ```sh
    velociraptor --embedded_config velociraptor-collector-amd64.exe config show
    ```
  '';

  sourcesTxt = writeText "SOURCES.txt" ''
    ================================================================================
    dfnix Field-Kit Stick v0 (${version}) — Component Licences & Source Provenance
    ================================================================================

    Every open-source component shipped on the dfnix field-kit stick (across
    KIT-WIN, KIT-MAC, and KIT-LNX) is listed below with its licence, upstream
    source URL, and cryptographic SHA-256 digest pinned in Nix.

    All components are built from source by Nix except WinPmem (whose Windows
    kernel driver must carry Microsoft's WHCP code-signing signature) and Fuji
    (a macOS application bundle distributed as a signed DMG).

    --------------------------------------------------------------------------------
    1. Velociraptor (KIT-WIN & KIT-LNX)
    --------------------------------------------------------------------------------
    Package:       velociraptor (windows-amd64, windows-arm64, linux-amd64, linux-arm64)
    Version:       ${velociraptor.version}
    Licence:       AGPL-3.0-only (GNU Affero General Public License v3.0 only)
    Homepage:      https://github.com/Velocidex/velociraptor
    Source URL:    https://github.com/Velocidex/velociraptor/archive/refs/tags/v${velociraptor.version}.tar.gz
    Source Hash:   ${velociraptor.src.outputHash}
    Vendor Hash:   ${velociraptor.vendorHash}

    --------------------------------------------------------------------------------
    2. WinPmem (KIT-WIN)
    --------------------------------------------------------------------------------
    Package:       winpmem
    Version:       ${winpmem.version}
    Licence:       Apache-2.0 (Apache License 2.0)
    Homepage:      https://github.com/Velocidex/WinPmem
    Source URL:    https://github.com/Velocidex/WinPmem/archive/refs/tags/v${winpmem.version}.tar.gz
    Source Hash:   sha256-OaX6h9bqbEFBwnwm++x1LgV+Yo3BLunA2Ek3K0NzXwM=
    Binary URLs & Hashes:
      - https://github.com/Velocidex/WinPmem/releases/download/v4.0.rc1/winpmem_mini_x64_rc2.exe
        SHA-256: sha256-pNUWtvyvO1sdTucJzob46r8dgCizqDEBR5t1aLkz0hs=
      - https://github.com/Velocidex/WinPmem/releases/download/v4.0.rc1/winpmem_mini_x86.exe
        SHA-256: sha256-3GqC/Gz9p5LTGC4H3hCtv7pCvzNu8mnbxAcyxLKuBSw=
      - https://github.com/Velocidex/WinPmem/releases/download/v4.0.rc1/go-winpmem_amd64_1.0-rc2_signed.exe
        SHA-256: sha256-hmkbtK8sF92exINMBKma1R4E94CgfRsFvDgqXRiS4MQ=

    --------------------------------------------------------------------------------
    3. Fuji (KIT-MAC)
    --------------------------------------------------------------------------------
    Package:       fuji
    Version:       ${fuji.version}
    Licence:       GPL-3.0-only (GNU General Public License v3.0 only)
    Homepage:      https://github.com/Lazza/Fuji
    Source URL:    https://github.com/Lazza/Fuji/archive/refs/tags/${fuji.version}.tar.gz
    Source Hash:   sha256-tJkwbdKeo3V9c5OHCty3n2l7CFqC8co67gQWqUilGlQ=
    Binary URL:    https://github.com/Lazza/Fuji/releases/download/${fuji.version}/FujiApp-${fuji.version}.dmg
    Binary Hash:   sha256-KCSuYrR70+hdoyNNNJYYoFFY2O27WXTi/zKrPJevNzI=

    --------------------------------------------------------------------------------
    4. UAC — Unix-like Artifact Collector (KIT-MAC & KIT-LNX)
    --------------------------------------------------------------------------------
    Package:       uac / uac-kit
    Version:       ${uac.version}
    Licence:       Apache-2.0 (Apache License 2.0)
    Homepage:      https://github.com/tclahr/uac
    Source URL:    https://github.com/tclahr/uac/archive/v${uac.version}.tar.gz
    Source Hash:   ${uac.src.outputHash}

    --------------------------------------------------------------------------------
    5. AVML — Acquire Volatile Memory for Linux (KIT-LNX & UAC bin/linux/*)
    --------------------------------------------------------------------------------
    Package:       avml (static musl x86_64 & aarch64)
    Version:       ${staticX86_64.avml.version}
    Licence:       MIT (MIT License)
    Homepage:      https://github.com/microsoft/avml
    Source URL:    https://github.com/microsoft/avml/archive/refs/tags/v${staticX86_64.avml.version}.tar.gz
    Source Hash:   ${staticX86_64.avml.src.outputHash}

    --------------------------------------------------------------------------------
    6. GNU coreutils (static musl x86_64 & aarch64 in UAC / uac-kit)
    --------------------------------------------------------------------------------
    Package:       coreutils-static
    Version:       ${staticX86_64.coreutils.version}
    Licence:       GPL-3.0-or-later (GNU General Public License v3.0 or later)
    Homepage:      https://www.gnu.org/software/coreutils/
    Source URL:    https://ftp.gnu.org/gnu/coreutils/coreutils-${staticX86_64.coreutils.version}.tar.xz
    Source Hash:   ${staticX86_64.coreutils.src.outputHash}

    --------------------------------------------------------------------------------
    7. GNU findutils (static musl x86_64 & aarch64 in uac-kit)
    --------------------------------------------------------------------------------
    Package:       findutils-static
    Version:       ${staticX86_64.findutils.version}
    Licence:       GPL-3.0-or-later (GNU General Public License v3.0 or later)
    Homepage:      https://www.gnu.org/software/findutils/
    Source URL:    https://ftp.gnu.org/gnu/findutils/findutils-${staticX86_64.findutils.version}.tar.xz
    Source Hash:   ${staticX86_64.findutils.src.outputHash}

    --------------------------------------------------------------------------------
    8. procps-ng (static musl x86_64 & aarch64 in uac-kit)
    --------------------------------------------------------------------------------
    Package:       procps-static
    Version:       ${staticX86_64.procps.version}
    Licence:       GPL-2.0-or-later AND LGPL-2.1-or-later
    Homepage:      https://gitlab.com/procps-ng/procps
    Source URL:    https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-${staticX86_64.procps.version}.tar.xz
    Source Hash:   ${staticX86_64.procps.src.outputHash}

    --------------------------------------------------------------------------------
    9. lsof (static musl x86_64 & aarch64 in uac-kit)
    --------------------------------------------------------------------------------
    Package:       lsof-static
    Version:       ${staticX86_64.lsof.version}
    Licence:       lsof (Purdue BSD-style License)
    Homepage:      https://github.com/lsof-org/lsof
    Source URL:    https://github.com/lsof-org/lsof/archive/refs/tags/${staticX86_64.lsof.version}.tar.gz
    Source Hash:   ${staticX86_64.lsof.src.outputHash}

    --------------------------------------------------------------------------------
    10. iproute2 (static musl x86_64 & aarch64 in uac-kit)
    --------------------------------------------------------------------------------
    Package:       iproute2-static
    Version:       ${staticX86_64.iproute2.version}
    Licence:       GPL-2.0-only (GNU General Public License v2.0 only)
    Homepage:      https://wiki.linuxfoundation.org/networking/iproute2
    Source URL:    https://www.kernel.org/pub/linux/utils/net/iproute2/iproute2-${staticX86_64.iproute2.version}.tar.xz
    Source Hash:   ${staticX86_64.iproute2.src.outputHash}

    --------------------------------------------------------------------------------
    11. net-tools (static musl x86_64 & aarch64 in uac-kit)
    --------------------------------------------------------------------------------
    Package:       net-tools-static
    Version:       ${staticX86_64.nettools.version}
    Licence:       GPL-2.0-or-later (GNU General Public License v2.0 or later)
    Homepage:      https://net-tools.sourceforge.io/
    Source URL:    https://sourceforge.net/projects/net-tools/files/net-tools-${staticX86_64.nettools.version}.tar.xz
    Source Hash:   ${staticX86_64.nettools.src.outputHash}

    --------------------------------------------------------------------------------
    12. BusyBox (static musl x86_64 & aarch64 in uac-kit)
    --------------------------------------------------------------------------------
    Package:       busybox-static
    Version:       ${staticX86_64.busybox.version}
    Licence:       GPL-2.0-only (GNU General Public License v2.0 only)
    Homepage:      https://busybox.net/
    Source URL:    https://busybox.net/downloads/busybox-${staticX86_64.busybox.version}.tar.bz2
    Source Hash:   ${staticX86_64.busybox.src.outputHash}

    --------------------------------------------------------------------------------
    13. dflive — Live System Companion & dfstream/1 Sender (KIT-WIN & KIT-LNX)
    --------------------------------------------------------------------------------
    Package:       dflive (windows-x86_64, linux-x86_64-static, linux-aarch64-static)
    Version:       ${dflive-static.version}
    Licence:       MIT OR Apache-2.0 (Dual-licensed under MIT and Apache License 2.0)
    Homepage:      ${dflive-source.url}
    Source URL:    ${dflive-source.url}
    Source Rev:    ${dflive-source.rev}
    Source Hash:   ${dflive-source.narHash}
    Linked Runtimes:
      - Linux static builds (dflive/x86_64/dflive, dflive/aarch64/dflive):
        statically linked against musl libc (${staticX86_64.musl.version}, MIT License);
        zero dynamic library dependencies.
      - Windows build (dflive.exe, PE32+ x86-64 console):
        statically links the mingw-w64 runtime (crt2.o, libmingwex.a, libmingw32.a;
        ZPL-2.1 / public domain) and GCC runtime unwind/intrinsics (libgcc.a,
        libgcc_eh.a; GPL-3.0-or-later WITH GCC-exception-3.1). Dynamically imports
        only standard Windows OS DLLs (advapi32.dll,
        api-ms-win-core-synch-l1-2-0.dll, bcrypt.dll, bcryptprimitives.dll,
        iphlpapi.dll, kernel32.dll, mpr.dll, msvcrt.dll, ntdll.dll, psapi.dll,
        userenv.dll, ws2_32.dll, wtsapi32.dll); runs without extra DLLs.
  '';

  packageMetadataJson = writeText "fieldkit-packages.json" (
    builtins.toJSON {
      inherit version;
      packages = {
        dfnix-fieldkit = {
          pname = "dfnix-fieldkit";
          inherit version;
          license = "MIT";
          source_url = "https://github.com/tylerstyle/dfnix";
          source_hash = "in-tree";
        };
        dflive = {
          pname = "dflive";
          version = dflive-static.version;
          license = "MIT OR Apache-2.0";
          source_url = dflive-source.url;
          source_rev = dflive-source.rev;
          source_hash = dflive-source.narHash;
        };
        velociraptor = {
          pname = "velociraptor";
          version = velociraptor.version;
          license = "AGPL-3.0-only";
          source_url = "https://github.com/Velocidex/velociraptor/archive/refs/tags/v${velociraptor.version}.tar.gz";
          source_hash = velociraptor.src.outputHash;
          vendor_hash = velociraptor.vendorHash;
        };
        winpmem = {
          pname = "winpmem";
          version = winpmem.version;
          license = "Apache-2.0";
          source_url = "https://github.com/Velocidex/WinPmem/archive/refs/tags/v${winpmem.version}.tar.gz";
          source_hash = "sha256-OaX6h9bqbEFBwnwm++x1LgV+Yo3BLunA2Ek3K0NzXwM=";
        };
        fuji = {
          pname = "fuji";
          version = fuji.version;
          license = "GPL-3.0-only";
          source_url = "https://github.com/Lazza/Fuji/archive/refs/tags/${fuji.version}.tar.gz";
          source_hash = "sha256-tJkwbdKeo3V9c5OHCty3n2l7CFqC8co67gQWqUilGlQ=";
          binary_url = "https://github.com/Lazza/Fuji/releases/download/${fuji.version}/FujiApp-${fuji.version}.dmg";
          binary_hash = "sha256-KCSuYrR70+hdoyNNNJYYoFFY2O27WXTi/zKrPJevNzI=";
        };
        uac = {
          pname = "uac";
          version = uac.version;
          license = "Apache-2.0";
          source_url = "https://github.com/tclahr/uac/archive/v${uac.version}.tar.gz";
          source_hash = uac.src.outputHash;
        };
        avml = {
          pname = "avml";
          version = staticX86_64.avml.version;
          license = "MIT";
          source_url = "https://github.com/microsoft/avml/archive/refs/tags/v${staticX86_64.avml.version}.tar.gz";
          source_hash = staticX86_64.avml.src.outputHash;
        };
        coreutils = {
          pname = "coreutils";
          version = staticX86_64.coreutils.version;
          license = "GPL-3.0-or-later";
          source_url = "https://ftp.gnu.org/gnu/coreutils/coreutils-${staticX86_64.coreutils.version}.tar.xz";
          source_hash = staticX86_64.coreutils.src.outputHash;
        };
        findutils = {
          pname = "findutils";
          version = staticX86_64.findutils.version;
          license = "GPL-3.0-or-later";
          source_url = "https://ftp.gnu.org/gnu/findutils/findutils-${staticX86_64.findutils.version}.tar.xz";
          source_hash = staticX86_64.findutils.src.outputHash;
        };
        procps = {
          pname = "procps";
          version = staticX86_64.procps.version;
          license = "GPL-2.0-or-later AND LGPL-2.1-or-later";
          source_url = "https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-${staticX86_64.procps.version}.tar.xz";
          source_hash = staticX86_64.procps.src.outputHash;
        };
        lsof = {
          pname = "lsof";
          version = staticX86_64.lsof.version;
          license = "lsof";
          source_url = "https://github.com/lsof-org/lsof/archive/refs/tags/${staticX86_64.lsof.version}.tar.gz";
          source_hash = staticX86_64.lsof.src.outputHash;
        };
        iproute2 = {
          pname = "iproute2";
          version = staticX86_64.iproute2.version;
          license = "GPL-2.0-only";
          source_url = "https://www.kernel.org/pub/linux/utils/net/iproute2/iproute2-${staticX86_64.iproute2.version}.tar.xz";
          source_hash = staticX86_64.iproute2.src.outputHash;
        };
        net-tools = {
          pname = "net-tools";
          version = staticX86_64.nettools.version;
          license = "GPL-2.0-or-later";
          source_url = "https://sourceforge.net/projects/net-tools/files/net-tools-${staticX86_64.nettools.version}.tar.xz";
          source_hash = staticX86_64.nettools.src.outputHash;
        };
        busybox = {
          pname = "busybox";
          version = staticX86_64.busybox.version;
          license = "GPL-2.0-only";
          source_url = "https://busybox.net/downloads/busybox-${staticX86_64.busybox.version}.tar.bz2";
          source_hash = staticX86_64.busybox.src.outputHash;
        };
      };
    }
  );

  manifestGenerator = writeText "generate-fieldkit-manifest.py" ''
    import hashlib
    import json
    import os
    import sys

    staging_dir = sys.argv[1]
    pkg_meta_path = sys.argv[2]
    out_json_path = sys.argv[3]

    with open(pkg_meta_path, "r", encoding="utf-8") as f:
        meta = json.load(f)

    pkgs = meta["packages"]

    FINDUTILS_BINS = {"find", "xargs"}
    PROCPS_BINS = {"free", "pgrep", "pidof", "pmap", "ps", "pwdx", "sysctl", "top", "uptime", "vmstat"}
    IPROUTE2_BINS = {"bridge", "ip", "lnstat", "nstat", "rtacct", "ss", "tc"}
    NETTOOLS_BINS = {"arp", "dnsdomainname", "hostname", "ifconfig", "netstat", "route"}

    def classify_file(part_label, rel_path):
        base = os.path.basename(rel_path)
        if rel_path == "dflive.exe" or rel_path.startswith("dflive/"):
            p = pkgs["dflive"]
            return ("dflive", p["version"], p["license"])
        if rel_path.startswith("winpmem/"):
            p = pkgs["winpmem"]
            return ("winpmem", p["version"], p["license"])
        if rel_path.startswith("velociraptor/"):
            if base.endswith(".exe") or base.startswith("velociraptor-linux-"):
                p = pkgs["velociraptor"]
                return ("velociraptor", p["version"], p["license"])
            p = pkgs["dfnix-fieldkit"]
            return ("dfnix-fieldkit", p["version"], p["license"])
        if rel_path == "Fuji.dmg":
            p = pkgs["fuji"]
            return ("fuji", p["version"], p["license"])
        if rel_path.startswith("avml/"):
            p = pkgs["avml"]
            return ("avml", p["version"], p["license"])
        if rel_path.startswith("uac/bin/linux/"):
            if base == "avml":
                p = pkgs["avml"]
                return ("avml", p["version"], p["license"])
            if base == "coreutils":
                p = pkgs["coreutils"]
                return ("coreutils", p["version"], p["license"])
            if base in FINDUTILS_BINS:
                p = pkgs["findutils"]
                return ("findutils", p["version"], p["license"])
            if base in PROCPS_BINS:
                p = pkgs["procps"]
                return ("procps", p["version"], p["license"])
            if base == "lsof":
                p = pkgs["lsof"]
                return ("lsof", p["version"], p["license"])
            if base in IPROUTE2_BINS:
                p = pkgs["iproute2"]
                return ("iproute2", p["version"], p["license"])
            if base in NETTOOLS_BINS:
                p = pkgs["net-tools"]
                return ("net-tools", p["version"], p["license"])
            if base == "busybox":
                p = pkgs["busybox"]
                return ("busybox", p["version"], p["license"])
        if rel_path.startswith("uac/"):
            p = pkgs["uac"]
            pkg_name = "uac-kit" if part_label == "KIT-LNX" else "uac"
            return (pkg_name, p["version"], p["license"])
        p = pkgs["dfnix-fieldkit"]
        return ("dfnix-fieldkit", p["version"], p["license"])

    def sha256_file(path):
        h = hashlib.sha256()
        with open(path, "rb") as f:
            while True:
                chunk = f.read(1024 * 1024)
                if not chunk:
                    break
                h.update(chunk)
        return h.hexdigest()

    PARTITIONS_SPEC = [
        {
            "number": 1,
            "label": "KIT-WIN",
            "filesystem": "exfat",
            "gpt_type_code": "0700",
            "gpt_type_guid": "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7",
            "gpt_partition_guid": "44464E49-5800-4B49-5400-000000000001",
            "gpt_readonly_bit60": True,
        },
        {
            "number": 2,
            "label": "KIT-MAC",
            "filesystem": "hfsplus",
            "gpt_type_code": "AF00",
            "gpt_type_guid": "48465300-0000-11AA-AA11-00306543ECAC",
            "gpt_partition_guid": "44464E49-5800-4B49-5400-000000000002",
            "gpt_readonly_bit60": True,
        },
        {
            "number": 3,
            "label": "KIT-LNX",
            "filesystem": "ext4",
            "gpt_type_code": "8300",
            "gpt_type_guid": "0FC63DAF-8483-4772-8E79-3D69D8477DE4",
            "gpt_partition_guid": "44464E49-5800-4B49-5400-000000000003",
            "gpt_readonly_bit60": True,
        },
        {
            "number": 4,
            "label": "KIT-OUT",
            "filesystem": "exfat",
            "gpt_type_code": "0700",
            "gpt_type_guid": "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7",
            "gpt_partition_guid": "44464E49-5800-4B49-5400-000000000004",
            "gpt_readonly_bit60": False,
        },
    ]

    partitions_out = []
    for pspec in PARTITIONS_SPEC:
        label = pspec["label"]
        pdir = os.path.join(staging_dir, label)
        files_list = []
        symlinks_list = []

        for root, dirs, files in os.walk(pdir, followlinks=False):
            dirs.sort()
            entries = sorted(dirs + files)
            for entry in entries:
                full = os.path.join(root, entry)
                rel = os.path.relpath(full, pdir).replace(os.sep, "/")
                if os.path.islink(full):
                    target = os.readlink(full)
                    pkg_name, pkg_ver, pkg_lic = classify_file(label, rel)
                    symlinks_list.append({
                        "path": rel,
                        "target": target,
                        "package": pkg_name,
                        "version": pkg_ver,
                        "license": pkg_lic,
                    })
                elif os.path.isfile(full):
                    pkg_name, pkg_ver, pkg_lic = classify_file(label, rel)
                    files_list.append({
                        "path": rel,
                        "size": os.path.getsize(full),
                        "sha256": sha256_file(full),
                        "package": pkg_name,
                        "version": pkg_ver,
                        "license": pkg_lic,
                    })

        files_list.sort(key=lambda x: x["path"])
        symlinks_list.sort(key=lambda x: x["path"])
        entry_out = dict(pspec)
        entry_out["file_count"] = len(files_list)
        entry_out["symlink_count"] = len(symlinks_list)
        entry_out["files"] = files_list
        entry_out["symlinks"] = symlinks_list
        partitions_out.append(entry_out)

    manifest = {
        "schema": "dfnix.fieldkit.manifest/v0",
        "version": meta["version"],
        "gpt_disk_guid": "44464E49-5800-4B49-5400-000000000000",
        "packages": pkgs,
        "partitions": partitions_out,
    }

    with open(out_json_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, sort_keys=False)
        f.write("\n")
  '';

  # Pure staging derivation: assembles all 4 partition trees, validates the
  # Velociraptor collector spec against the built Velociraptor binary, writes
  # per-partition KIT-MANIFEST.sha256 files, normalises permissions and
  # timestamps, and builds the combined JSON manifest.
  staging =
    runCommand "fieldkit-staging-${version}"
      {
        nativeBuildInputs = [
          python3
          velociraptor
        ];
      }
      ''
        set -euo pipefail

        # Validate that our collector-spec.yaml parses and defines DFNIX.Windows.Triage
        HOME="$TMPDIR" velociraptor --config ${velociraptorCollectorSpec} artifacts show DFNIX.Windows.Triage > /dev/null

        mkdir -p "$out/partitions/KIT-WIN/winpmem" \
                 "$out/partitions/KIT-WIN/velociraptor" \
                 "$out/partitions/KIT-MAC/.fseventsd" \
                 "$out/partitions/KIT-LNX/dflive/x86_64" \
                 "$out/partitions/KIT-LNX/dflive/aarch64" \
                 "$out/partitions/KIT-LNX/avml/x86_64" \
                 "$out/partitions/KIT-LNX/avml/aarch64" \
                 "$out/partitions/KIT-LNX/velociraptor" \
                 "$out/partitions/KIT-OUT/.fseventsd"

        # ----------------------------------------------------------------------
        # 1. KIT-WIN (exFAT)
        # ----------------------------------------------------------------------
        cp "${dflive-windows}/bin/dflive.exe" "$out/partitions/KIT-WIN/dflive.exe"
        chmod 0555 "$out/partitions/KIT-WIN/dflive.exe"

        cp "${winpmem}/share/winpmem/winpmem_mini_x64_rc2.exe" "$out/partitions/KIT-WIN/winpmem/"
        cp "${winpmem}/share/winpmem/winpmem_mini_x86.exe" "$out/partitions/KIT-WIN/winpmem/"
        cp "${winpmem}/share/winpmem/go-winpmem_amd64_1.0-rc2_signed.exe" "$out/partitions/KIT-WIN/winpmem/"

        cp "${velociraptor-windows-amd64}/bin/velociraptor.exe" "$out/partitions/KIT-WIN/velociraptor/velociraptor-windows-amd64.exe"
        cp "${velociraptor-windows-arm64}/bin/velociraptor.exe" "$out/partitions/KIT-WIN/velociraptor/velociraptor-windows-arm64.exe"
        cp "${velociraptorCollectorSpec}" "$out/partitions/KIT-WIN/velociraptor/collector-spec.yaml"
        cp "${velociraptorRepackMd}" "$out/partitions/KIT-WIN/velociraptor/REPACK.md"
        sed 's/$/\r/' "${velociraptorRepackMd}" > "$out/partitions/KIT-WIN/velociraptor/REPACK.txt"

        cp "${playbookWin}" "$out/partitions/KIT-WIN/live-windows.md"
        sed 's/$/\r/' "${playbookWin}" > "$out/partitions/KIT-WIN/live-windows.txt"
        sed 's/$/\r/' "${sourcesTxt}" > "$out/partitions/KIT-WIN/SOURCES.txt"

        # ----------------------------------------------------------------------
        # 2. KIT-MAC (HFS+)
        # ----------------------------------------------------------------------
        : > "$out/partitions/KIT-MAC/.metadata_never_index"
        : > "$out/partitions/KIT-MAC/.fseventsd/no_log"
        cp "${fuji}/share/fuji/Fuji.dmg" "$out/partitions/KIT-MAC/Fuji.dmg"
        cp -r "${uac}" "$out/partitions/KIT-MAC/uac"
        chmod -R u+w "$out/partitions/KIT-MAC/uac"
        cp "${playbookMac}" "$out/partitions/KIT-MAC/live-macos.md"
        cp "${sourcesTxt}" "$out/partitions/KIT-MAC/SOURCES.txt"

        # ----------------------------------------------------------------------
        # 3. KIT-LNX (ext4)
        # ----------------------------------------------------------------------
        cp -r "${uac-kit}" "$out/partitions/KIT-LNX/uac"
        chmod -R u+w "$out/partitions/KIT-LNX/uac"
        cp "${dflive-static}/bin/dflive" "$out/partitions/KIT-LNX/dflive/x86_64/dflive"
        cp "${dflive-aarch64-static}/bin/dflive" "$out/partitions/KIT-LNX/dflive/aarch64/dflive"
        chmod 0555 "$out/partitions/KIT-LNX/dflive/x86_64/dflive" "$out/partitions/KIT-LNX/dflive/aarch64/dflive"

        cp "${staticX86_64.avml}/bin/avml" "$out/partitions/KIT-LNX/avml/x86_64/avml"
        cp "${staticAarch64.avml}/bin/avml" "$out/partitions/KIT-LNX/avml/aarch64/avml"
        chmod 0555 "$out/partitions/KIT-LNX/avml/x86_64/avml" "$out/partitions/KIT-LNX/avml/aarch64/avml"

        cp "${velociraptor-linux-amd64}/bin/velociraptor" "$out/partitions/KIT-LNX/velociraptor/velociraptor-linux-amd64"
        cp "${velociraptor-linux-arm64}/bin/velociraptor" "$out/partitions/KIT-LNX/velociraptor/velociraptor-linux-arm64"
        chmod 0555 "$out/partitions/KIT-LNX/velociraptor/velociraptor-linux-amd64" "$out/partitions/KIT-LNX/velociraptor/velociraptor-linux-arm64"

        cp "${playbookLnx}" "$out/partitions/KIT-LNX/live-linux.md"
        cp "${sourcesTxt}" "$out/partitions/KIT-LNX/SOURCES.txt"

        # ----------------------------------------------------------------------
        # 4. KIT-OUT (exFAT)
        # ----------------------------------------------------------------------
        : > "$out/partitions/KIT-OUT/.metadata_never_index"
        : > "$out/partitions/KIT-OUT/.fseventsd/no_log"

        # ----------------------------------------------------------------------
        # Generate KIT-MANIFEST.sha256 on each tool partition (1..3)
        # ----------------------------------------------------------------------
        for part in KIT-WIN KIT-MAC KIT-LNX; do
          (
            cd "$out/partitions/$part"
            find . -type f ! -name 'KIT-MANIFEST.sha256' \
              | sed 's|^\./||' \
              | LC_ALL=C sort \
              | xargs -r -d '\n' sha256sum > KIT-MANIFEST.sha256
          )
        done

        # Mark all regular files read-only (0555 if executable, 0444 otherwise)
        # and fix timestamps to 1980-01-01T00:00:00Z across all partitions.
        find "$out/partitions" -type f -exec chmod a-w {} +
        find "$out/partitions" -exec touch -h -d "1980-01-01T00:00:00Z" {} +

        # Build the base JSON manifest with per-file hashes and package provenance
        python3 "${manifestGenerator}" "$out/partitions" "${packageMetadataJson}" "$out/manifest-base.json"
      '';
in
vmTools.runInLinuxVM (
  runCommand "dfnix-fieldkit-${version}"
    {
      inherit version;
      pname = "dfnix-fieldkit";
      memSize = 1024;
      QEMU_OPTS = "-drive file=fieldkit.img,format=raw,if=virtio,cache=unsafe,werror=report";
      nativeBuildInputs = [
        gptfdisk
        util-linux
        hfsprogs
        e2fsprogs
        exfatprogs
        attr
        kmod
        python3
      ];
      passthru = {
        inherit staging;
      };
      preVM = ''
        # 612 MiB raw image:
        #   1: KIT-WIN (192 MiB, exFAT,  GPT 0700, read-only bit 60)
        #   2: KIT-MAC ( 96 MiB, HFS+,  GPT AF00, read-only bit 60)
        #   3: KIT-LNX (256 MiB, ext4,  GPT 8300, read-only bit 60)
        #   4: KIT-OUT ( ~66 MiB, exFAT, GPT 0700, writable)
        truncate -s 612M fieldkit.img
      '';
      postVM = ''
        mkdir -p "$out"
        mv fieldkit.img "$out/fieldkit.img"
        (
          cd "$out"
          sha256sum fieldkit.img > fieldkit.img.sha256
        )
        img_sha256=$(awk '{print $1}' "$out/fieldkit.img.sha256")
        img_size=$(stat -c '%s' "$out/fieldkit.img")

        ${python3}/bin/python3 - "${staging}/manifest-base.json" "$out/manifest.json" "$img_size" "$img_sha256" <<'PY'
        import json
        import sys

        base_path, out_path, img_size, img_sha256 = sys.argv[1:5]
        with open(base_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        data["image"] = {
            "file": "fieldkit.img",
            "size": int(img_size),
            "sha256": img_sha256,
        }

        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, sort_keys=False)
            f.write("\n")
        PY

        ln -s manifest.json "$out/fieldkit-manifest.json"
        cp "${sourcesTxt}" "$out/SOURCES.txt"
      '';
      meta = {
        description = "Multi-partition forensic field-kit USB stick image (KIT-WIN, KIT-MAC, KIT-LNX, KIT-OUT) and manifest";
        license = with lib.licenses; [
          agpl3Only
          apache2
          gpl2Only
          gpl2Plus
          gpl3Only
          gpl3Plus
          lgpl21Plus
          lsof
          mit
        ];
        platforms = [ "x86_64-linux" ];
      };
    }
    ''
      set -euo pipefail

      echo "==> Partitioning /dev/vda with deterministic GPT GUIDs and bit 60 on partitions 1-3..."
      sgdisk -Z /dev/vda
      sgdisk \
        --disk-guid=44464E49-5800-4B49-5400-000000000000 \
        -n 1:2048:+192M -t 1:0700 -c 1:KIT-WIN -u 1:44464E49-5800-4B49-5400-000000000001 \
        -n 2:0:+96M     -t 2:AF00 -c 2:KIT-MAC -u 2:44464E49-5800-4B49-5400-000000000002 \
        -n 3:0:+256M    -t 3:8300 -c 3:KIT-LNX -u 3:44464E49-5800-4B49-5400-000000000003 \
        -n 4:0:+64M     -t 4:0700 -c 4:KIT-OUT -u 4:44464E49-5800-4B49-5400-000000000004 \
        -A 1:set:60 -A 2:set:60 -A 3:set:60 \
        /dev/vda

      partx -u /dev/vda

      mkdir -p /mnt/win /mnt/mac /mnt/lnx /mnt/out

      echo "==> Building Partition 1: KIT-WIN (exFAT)..."
      mkfs.exfat -L KIT-WIN -U 44464e49-5800-4b49-5400-000000000001 /dev/vda1
      tune.exfat -I 0x44464E01 /dev/vda1
      mount -t exfat /dev/vda1 /mnt/win
      cp -r --preserve=timestamps "${staging}/partitions/KIT-WIN/." /mnt/win/
      find /mnt/win -exec touch -h -d "1980-01-01T00:00:00Z" {} +
      sync
      umount /mnt/win

      echo "==> Building Partition 2: KIT-MAC (HFS+)..."
      mkfs.hfsplus -v KIT-MAC /dev/vda2
      mount -t hfsplus /dev/vda2 /mnt/mac
      cp -r --preserve=mode,timestamps,links "${staging}/partitions/KIT-MAC/." /mnt/mac/
      find /mnt/mac -exec touch -h -d "1980-01-01T00:00:00Z" {} +
      # Set HFS+ immutable flag (maps to macOS uchg/schg) on all regular files
      find /mnt/mac -type f -exec chattr +i {} +
      sync
      umount /mnt/mac

      echo "==> Building Partition 3: KIT-LNX (ext4 via mkfs.ext4 -d + chattr +i)..."
      E2FSPROGS_FAKE_TIME=1 mkfs.ext4 -F -L KIT-LNX \
        -U 44464e49-5800-4b49-5400-000000000003 \
        -E hash_seed=44464e49-5800-4b49-5400-000000000003 \
        -d "${staging}/partitions/KIT-LNX" \
        /dev/vda3
      mount -t ext4 /dev/vda3 /mnt/lnx
      find /mnt/lnx -type f -exec chattr +i {} +
      sync
      umount /mnt/lnx

      echo "==> Building Partition 4: KIT-OUT (exFAT)..."
      mkfs.exfat -L KIT-OUT -U 44464e49-5800-4b49-5400-000000000004 /dev/vda4
      tune.exfat -I 0x44464E04 /dev/vda4
      mount -t exfat /dev/vda4 /mnt/out
      cp -r --preserve=timestamps "${staging}/partitions/KIT-OUT/." /mnt/out/
      find /mnt/out -exec touch -h -d "1980-01-01T00:00:00Z" {} +
      sync
      umount /mnt/out

      sync
      blockdev --flushbufs /dev/vda
      echo "==> Field-kit image build complete."
    ''
)
