{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  # v4.0.rc1 ("Release 4.0 RC2") is the latest upstream release whose embedded
  # pmem kernel drivers (`winpmem_x64.sys` and `winpmem_x86.sys`) carry
  # production Microsoft signatures. (v4.1.dev1 is a prerelease with test-signed
  # drivers requiring `bcdedit /set testsigning on` + reboot.)
  #
  # Embedded driver signature chain (verified with `osslsigncode verify`):
  # - Signature Index 0 (Primary, cross-signed for Windows 7 / 8.1 / 2012 R2):
  #   Subject: `CN=Binalyze LLC, O=Binalyze LLC` -> `CN=GlobalSign CodeSigning CA - G3`
  #   -> `CN=GlobalSign Root CA` -> `CN=Microsoft Code Verification Root`
  #   (timestamped 2020-10-09 by GlobalSign TSA).
  # - Signature Index 1 (Nested, WHCP attestation-signed for Windows 10 / 11 with Secure Boot):
  #   Subject: `CN=Microsoft Windows Hardware Compatibility Publisher`
  #   -> `CN=Microsoft Windows Third Party Component CA 2014`
  #   -> `CN=Microsoft Root Certificate Authority 2010`
  #   (timestamped 2020-10-09 by `Microsoft Time-Stamp PCA 2010`).
  #   Note: Loads under Secure Boot on Windows 10/11, but HVCI / Memory Integrity
  #   (if enabled) blocks physical-memory mapping drivers via Microsoft's blocklist.
  #
  # Checklist tool recommendation:
  # - Primary recommendation for checklists: `winpmem_mini_x64_rc2.exe` (`winpmem_mini_x86.exe` on 32-bit).
  #   It has a ~515 KiB memory footprint (vs ~5 MiB for the Go wrapper), takes a
  #   single output path (`winpmem_mini_x64_rc2.exe physmem.raw`), and outputs a
  #   standard raw/ELF64 image directly consumable by Volatility 3.
  # - `go-winpmem_amd64_1.0-rc2_signed.exe` embeds the same dual-signed driver and
  #   is provided when AFF4 compressed output (`acquire --progress physmem.aff4`)
  #   is explicitly desired.
  # Upstream provides x64 and x86 binaries; no arm64 release binary exists.
  version = "4.0.rc1";

  miniX64 = fetchurl {
    url = "https://github.com/Velocidex/WinPmem/releases/download/v${version}/winpmem_mini_x64_rc2.exe";
    hash = "sha256-pNUWtvyvO1sdTucJzob46r8dgCizqDEBR5t1aLkz0hs=";
  };

  miniX86 = fetchurl {
    url = "https://github.com/Velocidex/WinPmem/releases/download/v${version}/winpmem_mini_x86.exe";
    hash = "sha256-3GqC/Gz9p5LTGC4H3hCtv7pCvzNu8mnbxAcyxLKuBSw=";
  };

  goWinpmemX64 = fetchurl {
    url = "https://github.com/Velocidex/WinPmem/releases/download/v${version}/go-winpmem_amd64_1.0-rc2_signed.exe";
    hash = "sha256-hmkbtK8sF92exINMBKma1R4E94CgfRsFvDgqXRiS4MQ=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "winpmem";
  inherit version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/winpmem" "$out/bin"
    cp ${miniX64} "$out/share/winpmem/winpmem_mini_x64_rc2.exe"
    cp ${miniX86} "$out/share/winpmem/winpmem_mini_x86.exe"
    cp ${goWinpmemX64} "$out/share/winpmem/go-winpmem_amd64_1.0-rc2_signed.exe"

    ln -s ../share/winpmem/winpmem_mini_x64_rc2.exe "$out/bin/winpmem_x64.exe"
    ln -s ../share/winpmem/winpmem_mini_x86.exe "$out/bin/winpmem_x86.exe"
    ln -s ../share/winpmem/go-winpmem_amd64_1.0-rc2_signed.exe "$out/bin/go-winpmem_x64.exe"

    runHook postInstall
  '';

  meta = {
    description = "Windows physical memory acquisition tool with signed kernel drivers (x64 and x86)";
    homepage = "https://github.com/Velocidex/WinPmem";
    license = lib.licenses.apache2;
    platforms = lib.platforms.all;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
