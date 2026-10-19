{ config, lib, pkgs, ... }:

with lib;

let
  # Rockey4ND / Feitian HID dongles call HidD_FlushQueue right after HidD_SetFeature.
  # Wine's hidclass.sys/hid.dll returns STATUS_NOT_SUPPORTED (0xc00000bb) for IOCTL_HID_FLUSH_QUEUE (0xb0197),
  # causing the dongle communication library to fail and trigger the "waiting for dongle" popup.
  # We dynamically parse and patch HidD_FlushQueue in Wine's PE hid.dll (64-bit and 32-bit)
  # to immediately return TRUE (1), allowing the Rockey4 cryptographic handshake to succeed seamlessly.
  pePatchScript = ''
    import struct, sys

    def patch_hid(src_path, dst_path, is_32bit):
        with open(src_path, "rb") as f:
            data = bytearray(f.read())
        pe_offset = struct.unpack_from("<I", data, 0x3c)[0]
        num_sections = struct.unpack_from("<H", data, pe_offset + 6)[0]
        opt_hdr_size = struct.unpack_from("<H", data, pe_offset + 20)[0]
        sec_offset = pe_offset + 24 + opt_hdr_size
        magic = struct.unpack_from("<H", data, pe_offset + 24)[0]
        is_64 = (magic == 0x20b)

        sections = []
        for i in range(num_sections):
            sec = data[sec_offset + i*40 : sec_offset + (i+1)*40]
            name = sec[:8].rstrip(b"\x00").decode("latin-1")
            vsize, va, rsize, rptr = struct.unpack_from("<IIII", sec, 8)
            sections.append((name, va, vsize, rptr, rsize))

        def rva_to_offset(rva):
            for name, va, vsize, rptr, rsize in sections:
                if va <= rva < va + vsize:
                    return rptr + (rva - va)
            return None

        opt_offset = pe_offset + 24
        data_dir = opt_offset + (112 if is_64 else 96)
        export_rva, export_size = struct.unpack_from("<II", data, data_dir)
        export_offset = rva_to_offset(export_rva)
        num_funcs, num_names, funcs_rva, names_rva, ords_rva = struct.unpack_from("<IIIII", data, export_offset + 20)
        funcs_off = rva_to_offset(funcs_rva)
        names_off = rva_to_offset(names_rva)
        ords_off = rva_to_offset(ords_rva)

        target_func_rva = None
        for i in range(num_names):
            name_rva = struct.unpack_from("<I", data, names_off + i*4)[0]
            name_off = rva_to_offset(name_rva)
            fn_name = data[name_off:data.find(b"\x00", name_off)].decode("ascii")
            if fn_name == "HidD_FlushQueue":
                ord_val = struct.unpack_from("<H", data, ords_off + i*2)[0]
                target_func_rva = struct.unpack_from("<I", data, funcs_off + ord_val*4)[0]
                break

        if target_func_rva is None:
            sys.exit(f"HidD_FlushQueue not found in {src_path}")

        # W6 Hardening:
        # 1. Forwarded export check: In PE format, if func_rva falls within export directory [export_rva, export_rva + export_size),
        #    it is a forwarder string (e.g. "NTDLL.RtlAllocateHeap"), not executable code!
        if export_rva <= target_func_rva < export_rva + export_size:
            sys.exit(f"HidD_FlushQueue in {src_path} is a forwarded export (RVA {hex(target_func_rva)}); cannot patch code.")

        # 2. Section bounds check: Verify that target_func_rva and patch bytes lie strictly within .text section
        text_sec = None
        for sec in sections:
            if sec[0] == ".text":
                text_sec = sec
                break
        if text_sec is None:
            sys.exit(f".text section not found in {src_path}")

        _, t_va, t_vsize, t_rptr, t_rsize = text_sec
        patch = b"\xb8\x01\x00\x00\x00\xc3" if is_64 else b"\xb8\x01\x00\x00\x00\xc2\x04\x00"
        patch_len = len(patch)

        if not (t_va <= target_func_rva and target_func_rva + patch_len <= t_va + t_vsize):
            sys.exit(f"Target function RVA {hex(target_func_rva)} out of .text virtual bounds [{hex(t_va)}, {hex(t_va + t_vsize)})")

        target_offset = t_rptr + (target_func_rva - t_va)
        if not (t_rptr <= target_offset and target_offset + patch_len <= t_rptr + t_rsize):
            sys.exit(f"Target file offset {hex(target_offset)} out of .text raw bounds [{hex(t_rptr)}, {hex(t_rptr + t_rsize)})")

        data[target_offset:target_offset + patch_len] = patch
        with open(dst_path, "wb") as f:
            f.write(data)

    patch_hid(sys.argv[1], sys.argv[2], sys.argv[3] == "32")
  '';

  patchedWineHid64 = pkgs.runCommand "wine-hid64-patched.dll" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    python3 -c '${pePatchScript}' "${pkgs.wineWow64Packages.stable}/lib/wine/x86_64-windows/hid.dll" "$out" "64"
  '';

  patchedWineHid32 = pkgs.runCommand "wine-hid32-patched.dll" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    python3 -c '${pePatchScript}' "${pkgs.wineWow64Packages.stable}/lib/wine/i386-windows/hid.dll" "$out" "32"
  '';

  # Dedicated X-Ways launcher with root privilege auto-elevation,
  # graphical session preservation, Wine prefix management,
  # Feitian/CodeMeter dongle support, forensic audit trail, and raw physical disk mapping.
  xwaysLauncher = pkgs.writeShellApplication {
    name = "xways";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
      gawk
      gnused
      util-linux
      jq
      dfcore
      xhost
      glibc.bin
      wineWow64Packages.stable
    ];
    text = ''
      echo "=== X-Ways Forensics Wine Environment Initializer ==="

      # 0. Ensure root privileges for raw physical drive access, dongle hardware access,
      # and write access to targets mounted by dfmount (which are owned by root:root).
      if [[ $EUID -ne 0 ]]; then
        USER_WAYLAND="''${WAYLAND_DISPLAY:-}"
        USER_XDG="''${XDG_RUNTIME_DIR:-/run/user/$UID}"
        USER_DISP="''${DISPLAY:-}"
        USER_XAUTH="''${XAUTHORITY:-$HOME/.Xauthority}"
        USER_NIRI="''${NIRI_SOCKET:-}"

        if [[ -z "$USER_NIRI" && -d "$USER_XDG" ]]; then
          for sock in "$USER_XDG"/niri*.sock; do
            if [[ -S "$sock" ]]; then
              USER_NIRI="$sock"
              break
            fi
          done
        fi

        echo "[*] Elevating to root for raw block device, dongle, and target write access..."
        exec sudo \
          WAYLAND_DISPLAY="$USER_WAYLAND" \
          XDG_RUNTIME_DIR="$USER_XDG" \
          DISPLAY="$USER_DISP" \
          XAUTHORITY="$USER_XAUTH" \
          NIRI_SOCKET="$USER_NIRI" \
          TARGET_USER="$USER" \
          TARGET_UID="$UID" \
          "$0" "$@"
      fi

      # 0b. Enter an isolated mount namespace for bind-mounting the patched hid.dll over Wine's PE files
      if [[ -z "''${XWAYS_NS_ACTIVE:-}" ]]; then
        export XWAYS_NS_ACTIVE=1
        exec unshare -m -- "$0" "$@"
      fi

      # Intercept Wine's hid.dll with our patched version to ensure Feitian/Rockey4 dongles authenticate cleanly
      # unshare -m defaults to private mount propagation, but make-rprivate ensures submount changes never leak
      mount --make-rprivate / 2>/dev/null || true
      mount --bind "${patchedWineHid64}" "${pkgs.wineWow64Packages.stable}/lib/wine/x86_64-windows/hid.dll"
      mount --bind "${patchedWineHid32}" "${pkgs.wineWow64Packages.stable}/lib/wine/i386-windows/hid.dll"

      # Capture invoking examiner user and real home directory before resetting HOME for Wine root execution
      CALLING_USER="''${SUDO_USER:-$USER}"
      REAL_HOME="$(getent passwd "$CALLING_USER" 2>/dev/null | cut -d: -f6 || true)"
      if [[ -z "$REAL_HOME" || "$REAL_HOME" == "/root" ]]; then
        if [[ -d "/home/$CALLING_USER" && "$CALLING_USER" != "root" ]]; then
          REAL_HOME="/home/$CALLING_USER"
        elif [[ -d "/home/nixos" ]]; then
          REAL_HOME="/home/nixos"
        else
          REAL_HOME="/root"
        fi
      fi

      # 1. Recover/Normalize Graphical Session Environment for Root
      export HOME="/root"
      export WINEPREFIX="/root/.wine"
      mkdir -p "/root"
      umask 0002

      # If WAYLAND_DISPLAY or XDG_RUNTIME_DIR was not passed, discover it from active user session
      if [[ -z "''${WAYLAND_DISPLAY:-}" || -z "''${XDG_RUNTIME_DIR:-}" ]]; then
        for u_dir in /run/user/1000 /run/user/*; do
          if [[ -d "$u_dir" ]]; then
            for sock in "$u_dir"/wayland-*; do
              if [[ -S "$sock" ]]; then
                XDG_RUNTIME_DIR="$u_dir"
                export XDG_RUNTIME_DIR
                WAYLAND_DISPLAY="$(basename "$sock")"
                export WAYLAND_DISPLAY
                break 2
              fi
            done
          fi
        done
      fi

      if [[ -z "''${NIRI_SOCKET:-}" && -n "''${XDG_RUNTIME_DIR:-}" ]]; then
        for sock in "''${XDG_RUNTIME_DIR}"/niri*.sock; do
          if [[ -S "$sock" ]]; then
            export NIRI_SOCKET="$sock"
            break
          fi
        done
      fi

      if [[ -z "''${DISPLAY:-}" && -e /tmp/.X11-unix/X0 ]]; then
        export DISPLAY=":0"
      fi

      if [[ -z "''${XAUTHORITY:-}" && -f "$REAL_HOME/.Xauthority" ]]; then
        export XAUTHORITY="$REAL_HOME/.Xauthority"
      fi

      # Authorize root on X11 if display is active
      if command -v xhost >/dev/null 2>&1 && [[ -n "''${DISPLAY:-}" ]]; then
        xhost +si:localuser:root >/dev/null 2>&1 || true
      fi

      # 2. Parse Options and Locate X-Ways Executable
      USE_DESKTOP="''${XWAYS_DESKTOP:-0}"
      DESKTOP_RES="''${XWAYS_DESKTOP_RES:-}"
      TRUST_PATH=0
      TARGET_ARG=""
      PASSTHROUGH_ARGS=()

      while [[ $# -gt 0 ]]; do
        case "$1" in
          -d|--desktop)
            USE_DESKTOP=1
            shift
            ;;
          -r|--res|--resolution)
            if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
              echo "Error: -r/--res/--resolution requires a resolution argument (e.g. 1920x1080)" >&2
              exit 1
            fi
            DESKTOP_RES="$2"
            shift 2
            ;;
          --desktop=*)
            USE_DESKTOP=1
            DESKTOP_RES="''${1#*=}"
            shift
            ;;
          --trust-path)
            TRUST_PATH=1
            shift
            ;;
          -h|--help)
            echo "Usage: xways [options] [/path/to/portable/folder or .exe] [xways args...]"
            echo ""
            echo "Options:"
            echo "  -d, --desktop                Run in Wine Virtual Desktop container (isolates all popups/dialogs)"
            echo "  -r, --res, --resolution WxH  Set virtual desktop resolution (e.g. 1920x1080). Auto-detects display if omitted"
            echo "  --trust-path                 Override forensic trust path verification for non-standard exe location"
            echo "  -h, --help                   Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  XWAYS_DESKTOP=1              Default to virtual desktop mode"
            echo "  XWAYS_DESKTOP_RES=WxH        Default resolution for virtual desktop"
            exit 0
            ;;
          *)
            if [[ -z "$TARGET_ARG" ]]; then
              if [[ -d "$1" ]]; then
                TARGET_ARG="$1"
              elif [[ -f "$1" && "$1" =~ \.[eE][xX][eE]$ ]]; then
                TARGET_ARG="$1"
              else
                PASSTHROUGH_ARGS+=("$1")
              fi
            else
              PASSTHROUGH_ARGS+=("$1")
            fi
            shift
            ;;
        esac
      done

      TARGET_EXE=""

      # If target argument is a directory, search inside it first
      if [[ -n "$TARGET_ARG" && -d "$TARGET_ARG" ]]; then
        SEARCH_DIR="$TARGET_ARG"
        # 1st Priority in directory: 64-bit Forensics
        FOUND=$(find "$SEARCH_DIR" -maxdepth 3 -iname "xwforensics64.exe" 2>/dev/null | head -n1 || true)
        if [[ -n "$FOUND" ]]; then
          TARGET_EXE="$FOUND"
        else
          FOUND=$(find "$SEARCH_DIR" -maxdepth 3 -iname "xwforensics.exe" 2>/dev/null | head -n1 || true)
          if [[ -n "$FOUND" ]]; then
            TARGET_EXE="$FOUND"
          else
            FOUND=$(find "$SEARCH_DIR" -maxdepth 3 \( -iname "xwinvestigator64.exe" -o -iname "xwinvestigator.exe" \) 2>/dev/null | head -n1 || true)
            if [[ -n "$FOUND" ]]; then
              TARGET_EXE="$FOUND"
            fi
          fi
        fi
      elif [[ -n "$TARGET_ARG" && -f "$TARGET_ARG" ]]; then
        TARGET_EXE="$TARGET_ARG"
      fi

      if [[ -z "$TARGET_EXE" ]]; then
        # Search strictly in trusted application locations (never untrusted evidence mounts)
        SEARCH_PATHS=(
          "/opt/xways"
          "/etc/xways"
          "''${REAL_HOME}/xways"
          "''${REAL_HOME}/Desktop/xways"
          "/root/xways"
          "/root/Desktop/xways"
        )
        for t_dir in /media/target/*/xways /media/target/xways; do
          if [[ -d "$t_dir" ]]; then
            SEARCH_PATHS+=("$t_dir")
          fi
        done

        # 1st Priority: 64-bit Forensics (optimal for memory-intensive forensic workloads)
        for sp in "''${SEARCH_PATHS[@]}"; do
          if [[ -d "$sp" ]]; then
            FOUND=$(find "$sp" -maxdepth 5 -iname "xwforensics64.exe" 2>/dev/null | head -n1 || true)
            if [[ -n "$FOUND" ]]; then
              TARGET_EXE="$FOUND"
              break
            fi
          fi
        done

        # 2nd Priority: 32-bit Forensics fallback
        if [[ -z "$TARGET_EXE" ]]; then
          for sp in "''${SEARCH_PATHS[@]}"; do
            if [[ -d "$sp" ]]; then
              FOUND=$(find "$sp" -maxdepth 5 -iname "xwforensics.exe" 2>/dev/null | head -n1 || true)
              if [[ -n "$FOUND" ]]; then
                TARGET_EXE="$FOUND"
                break
              fi
            fi
          done
        fi

        # 3rd Priority: Investigator editions fallback
        if [[ -z "$TARGET_EXE" ]]; then
          for sp in "''${SEARCH_PATHS[@]}"; do
            if [[ -d "$sp" ]]; then
              FOUND=$(find "$sp" -maxdepth 5 \( -iname "xwinvestigator64.exe" -o -iname "xwinvestigator.exe" \) 2>/dev/null | head -n1 || true)
              if [[ -n "$FOUND" ]]; then
                TARGET_EXE="$FOUND"
                break
              fi
            fi
          done
        fi
      fi

      if [[ -z "$TARGET_EXE" || ! -f "$TARGET_EXE" ]]; then
        echo "[!] Error: No X-Ways executable found in trusted locations." >&2
        echo "Usage: xways [options] [/path/to/portable/folder or .exe] [xways args...]" >&2
        echo "Or ensure your portable X-Ways folder is in /opt/xways, ~/Desktop/xways, or /media/target/*/xways." >&2
        exit 1
      fi

      # Forensic Safety Verification (H2): Refuse execution of any binary on evidence, read-only, or untrusted paths
      REAL_TARGET="$(realpath "$TARGET_EXE" 2>/dev/null || echo "$TARGET_EXE")"
      REFUSAL_REASON=""
      REFUSAL_MSG=""

      # 1. Evidence mount refusal
      if [[ "$REAL_TARGET" == "/media/evidence"* || "$REAL_TARGET" == "/media/evidence" ]]; then
        REFUSAL_REASON="exe_under_evidence_mount"
        REFUSAL_MSG="Refusing to execute binary from evidence path: $REAL_TARGET. Suspect media must never supply analysis executables."
      fi

      # 2. Read-only filesystem refusal (e.g. ro target shares or read-only evidence mounts)
      if [[ -z "$REFUSAL_REASON" ]]; then
        MNT_OPTS="$(findmnt -no OPTIONS -T "$REAL_TARGET" 2>/dev/null || true)"
        if [[ ",$MNT_OPTS," == *",ro,"* ]]; then
          REFUSAL_REASON="exe_on_readonly_filesystem"
          REFUSAL_MSG="Refusing to execute binary on read-only filesystem ($MNT_OPTS): $REAL_TARGET. Read-only mounts are treated as evidence."
        fi
      fi

      # 3. Path allowlist check (unless --trust-path was specified)
      if [[ -z "$REFUSAL_REASON" && "$TRUST_PATH" -ne 1 ]]; then
        IS_ALLOWLISTED=0
        ALLOWLIST_PREFIXES=(
          "/opt/xways"
          "/etc/xways"
          "''${REAL_HOME}/xways"
          "''${REAL_HOME}/Desktop/xways"
          "/root/xways"
          "/root/Desktop/xways"
        )
        for pfx in "''${ALLOWLIST_PREFIXES[@]}"; do
          if [[ "$REAL_TARGET" == "$pfx" || "$REAL_TARGET" == "$pfx/"* ]]; then
            IS_ALLOWLISTED=1
            break
          fi
        done
        if [[ "$IS_ALLOWLISTED" -eq 0 ]]; then
          for t_dir in /media/target/*/xways /media/target/xways; do
            if [[ -d "$t_dir" && ( "$REAL_TARGET" == "$t_dir" || "$REAL_TARGET" == "$t_dir/"* ) ]]; then
              IS_ALLOWLISTED=1
              break
            fi
          done
        fi

        if [[ "$IS_ALLOWLISTED" -eq 0 ]]; then
          REFUSAL_REASON="exe_path_not_allowlisted"
          REFUSAL_MSG="Refusing to execute binary outside trusted application roots: $REAL_TARGET (use --trust-path to override)"
        fi
      fi

      # If refused, report to stderr and log audit record
      if [[ -n "$REFUSAL_REASON" ]]; then
        echo "[!] CRITICAL FORENSIC SAFETY REFUSAL: $REFUSAL_MSG" >&2
        REFUSAL_DETAILS=$(jq -n \
          --arg path "$REAL_TARGET" \
          --arg reason "$REFUSAL_REASON" \
          '{path: $path, refusal_reason: $reason}')
        if ! dfcore-audit record \
          --tool xways \
          --action launch \
          --outcome refused \
          --details "$REFUSAL_DETAILS" \
          --message "$REFUSAL_MSG"; then
          echo "[!] audit record failed: could not record refused launch" >&2
        fi
        exit 1
      fi

      TARGET_SHA256="$(sha256sum "$REAL_TARGET" | awk '{print $1}')"
      echo "[*] Found X-Ways executable: $TARGET_EXE"
      echo "[*] SHA-256: $TARGET_SHA256  $REAL_TARGET"
      if [[ "$TRUST_PATH" -eq 1 ]]; then
        echo "[!] NOTICE: Examiner overridden path trust verification with --trust-path"
      fi

      EXE_DIR="$(dirname "$REAL_TARGET")"
      EXE_NAME="$(basename "$REAL_TARGET")"

      # 3. Check Feitian / CodeMeter License Dongle (B1: case-insensitive vendor detection)
      echo "[*] Checking for connected forensic license dongles..."
      DONGLE_FOUND=0
      shopt -s nullglob
      uevents=(/sys/class/hidraw/*/device/uevent)
      shopt -u nullglob

      if [[ ''${#uevents[@]} -gt 0 ]]; then
        if grep -qi "096e" "''${uevents[@]}" 2>/dev/null; then
          echo "[✓] Feitian HID security dongle detected (096e)."
          DONGLE_FOUND=1
        elif grep -qi "064f" "''${uevents[@]}" 2>/dev/null; then
          echo "[✓] CodeMeter security dongle detected (064f)."
          DONGLE_FOUND=1
        fi
      fi
      if [[ $DONGLE_FOUND -eq 0 ]]; then
        echo "[*] Note: Hardware dongle not detected on HID raw interface."
      fi

      # 4. Setup Wine Prefix and DOS Devices
      WINE_DIR="$WINEPREFIX"
      DOS_DIR="$WINE_DIR/dosdevices"

      WINE_BIN="${pkgs.wineWow64Packages.stable}/bin/wine"
      if [ ! -x "$WINE_BIN" ] && [ -x "${pkgs.wineWow64Packages.stable}/bin/wine64" ]; then
        WINE_BIN="${pkgs.wineWow64Packages.stable}/bin/wine64"
      fi
      WINESERVER_BIN="${pkgs.wineWow64Packages.stable}/bin/wineserver"

      # Initialize Wine prefix cleanly if drive_c or system32 does not exist,
      # or if winebus root PnP device tree is missing from the registry
      if [[ ! -d "$WINE_DIR/drive_c/windows/system32" ]] || ! grep -q "WINEBUS" "$WINE_DIR/system.reg" 2>/dev/null; then
        echo "[*] Initializing Wine environment (first run after boot takes ~10-15 seconds)..."
        rm -rf "$DOS_DIR" 2>/dev/null || true
        WINEDLLOVERRIDES="mscoree,mshtml=" WINEDEBUG="-all" "$WINE_BIN" wineboot -i
        if [[ -x "$WINESERVER_BIN" ]]; then
          "$WINESERVER_BIN" -w 2>/dev/null || true
        fi

        # W1: Import winebus and direct HID raw registry settings in one atomic regedit call
        echo "[*] Configuring winebus and direct HID raw device access..."
        REG_FILE=$(mktemp /tmp/winebus-XXXXXX.reg)
        cat << "EOF" > "$REG_FILE"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\winebus]
"ImagePath"=hex(2):73,00,79,00,73,00,74,00,65,00,6d,00,33,00,32,00,5c,00,64,00,72,00,69,00,76,00,65,00,72,00,73,00,5c,00,77,00,69,00,6e,00,65,00,62,00,75,00,73,00,2e,00,73,00,79,00,73,00,00,00
"Type"=dword:00000001
"Start"=dword:00000002
"ErrorControl"=dword:00000001
"Group"="WinePlugPlay"
"DisableHidraw"=dword:00000000
"Enable SDL"=dword:00000000

[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\winehid]
"ImagePath"=hex(2):73,00,79,00,73,00,74,00,65,00,6d,00,33,00,32,00,5c,00,64,00,72,00,69,00,76,00,65,00,72,00,73,00,5c,00,77,00,69,00,6e,00,65,00,68,00,69,00,64,00,2e,00,73,00,79,00,73,00,00,00
"Type"=dword:00000001
"Start"=dword:00000003
"ErrorControl"=dword:00000001
"Group"="WinePlugPlay"

[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Enum\ROOT\WINE\WINEBUS]
"Class"="System"
"ClassGUID"="{4D36E97D-E325-11CE-BFC1-08002BE10318}"
"DeviceDesc"="Wine HID bus driver"
"HardwareId"=hex(7):72,00,6f,00,6f,00,74,00,5c,00,77,00,69,00,6e,00,65,00,62,00,75,00,73,00,00,00,00,00
"Service"="winebus"
EOF
        WINEDEBUG="-all" "$WINE_BIN" regedit /S "$REG_FILE" >/dev/null 2>&1 || true
        rm -f "$REG_FILE"

        if [[ -x "$WINESERVER_BIN" ]]; then
          "$WINESERVER_BIN" -k 2>/dev/null || true
          "$WINESERVER_BIN" -w 2>/dev/null || true
        fi
      fi

      mkdir -p "$DOS_DIR"

      # H1: Drop Z: = / to prevent arbitrary filesystem write escalation from Wine root.
      rm -f "$DOS_DIR/z:" "$DOS_DIR/z::"

      # Ensure C: and X: DOS drives are linked properly (X: = program folder)
      ln -sfn ../drive_c "$DOS_DIR/c:"
      ln -sfn "$EXE_DIR" "$DOS_DIR/x:"

      # Map forensic mountpoints to dedicated DOS drive letters for convenience
      if [[ -d /media/target ]]; then
        ln -sfn /media/target "$DOS_DIR/t:"
      fi
      if [[ -d /media/evidence ]]; then
        ln -sfn /media/evidence "$DOS_DIR/e:"
      fi
      if [[ -d /media ]]; then
        ln -sfn /media "$DOS_DIR/m:"
      fi
      if [[ -d /run/media ]]; then
        ln -sfn /run/media "$DOS_DIR/r:"
      fi

      # H4: Map physical block devices for raw physical drive inspection
      # Exclude protected devices (system disk and live ISO medium)
      echo "[*] Mapping physical drives into Wine dosdevices for raw forensics inspection..."
      letters=(d f g h i j k l n o p q s u v w y)
      idx=0

      PROTECTED_FILE="''${DFNIX_PROTECTED_FILE:-/run/dfnix/protected.json}"
      PROT_JSON="{}"
      if [[ -f "$PROTECTED_FILE" ]]; then
        PROT_JSON="$(cat "$PROTECTED_FILE" 2>/dev/null || echo "{}")"
      fi

      DRIVE_ENTRIES=()

      while IFS=$'\t' read -r DEV_PATH DEV_KNAME _DEV_MAJMIN DEV_MODEL DEV_SERIAL _DEV_WWN DEV_SIZE DEV_TYPE IS_PROTECTED; do
        [[ "$DEV_TYPE" == "disk" ]] || continue
        KNAME_BASE="$(basename "$DEV_KNAME")"
        [[ "$KNAME_BASE" =~ ^(sd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$ ]] || continue

        if [[ "$IS_PROTECTED" -eq 1 ]]; then
          echo "    Skipping protected system device: $DEV_PATH (''${DEV_MODEL:--}, ''${DEV_SIZE:--})"
          continue
        fi

        if [[ $idx -lt ''${#letters[@]} ]]; then
          letter="''${letters[$idx]}"
          target_link="$DOS_DIR/''${letter}::"
          rm -f "$target_link"
          ln -s "$DEV_PATH" "$target_link"
          printf "    Mapped raw drive %-14s -> %s::  (Model: %-20s Serial: %-15s Size: %s)\n" \
            "$DEV_PATH" "$letter" "''${DEV_MODEL:--}" "''${DEV_SERIAL:--}" "''${DEV_SIZE:--}"

          DRIVE_JSON=$(jq -n \
            --arg letter "$letter" \
            --arg dev "$DEV_PATH" \
            --arg model "''${DEV_MODEL:-}" \
            --arg serial "''${DEV_SERIAL:-}" \
            --arg size "''${DEV_SIZE:-}" \
            '{($letter): {device: $dev, model: $model, serial: $serial, size: $size}}')
          DRIVE_ENTRIES+=("$DRIVE_JSON")

          idx=$((idx + 1))
        fi
      done < <(lsblk -J -p -o NAME,KNAME,MAJ:MIN,MODEL,SERIAL,WWN,SIZE,TYPE 2>/dev/null | jq -r --argjson prot "$PROT_JSON" '
        def is_prot:
          . as $d |
          any(($prot.devices[]?.identity // empty);
            . as $p |
            (
              ((($p.wwn // "") != "") and (($d.wwn // "") != "") and (($p.wwn | ascii_downcase) == ($d.wwn | ascii_downcase)))
              or
              ((($p.serial // "") != "") and (($d.serial // "") != "") and ($p.serial == $d.serial))
              or
              ((($p.diskseq // "") != "") and (($d.diskseq // "") != "") and ($p.diskseq == $d.diskseq))
              or
              (((($p.serial // "") == "") and (($p.wwn // "") == "") and (($p.diskseq // "") == "")) and (
                (($p.path // "") == $d.name) or
                ((($p.kernel_name // "") | sub("^/dev/"; "")) == (($d.kname // "") | sub("^/dev/"; ""))) or
                (((($p.maj_min // "") != "")) and ($p.maj_min == $d["maj:min"]))
              ))
            )
          );
        .blockdevices[]? | select(.type == "disk") |
        [
          .name,
          .kname,
          (."maj:min" // "-"),
          (.model // "-"),
          (.serial // "-"),
          (.wwn // "-"),
          (.size // "-"),
          .type,
          (if is_prot then 1 else 0 end)
        ] | @tsv
      ' 2>/dev/null || true)

      if [[ ''${#DRIVE_ENTRIES[@]} -gt 0 ]]; then
        DRIVES_OBJ=$(jq -s 'add' <<< "''${DRIVE_ENTRIES[@]}")
      else
        DRIVES_OBJ="{}"
      fi

      # 5. Launch X-Ways under Wine
      # Double check Z: removal right before execution (wineboot can regenerate it)
      rm -f "$DOS_DIR/z:" "$DOS_DIR/z::"

      LAUNCH_MODE="native"
      if [[ "$USE_DESKTOP" -eq 1 ]]; then
        LAUNCH_MODE="desktop"
      fi

      LAUNCH_DETAILS=$(jq -n \
        --arg path "$REAL_TARGET" \
        --arg sha256 "$TARGET_SHA256" \
        --arg mode "$LAUNCH_MODE" \
        --argjson trust_override "$([ "$TRUST_PATH" -eq 1 ] && echo true || echo false)" \
        --argjson drives "$DRIVES_OBJ" \
        '{path: $path, sha256: $sha256, mode: $mode, trust_path_override: $trust_override, drives: $drives}')

      if ! dfcore-audit record \
        --tool xways \
        --action launch \
        --outcome ok \
        --details "$LAUNCH_DETAILS" \
        --message "Launched $EXE_NAME in mode $LAUNCH_MODE"; then
        echo "[!] audit record failed: could not record launch" >&2
      fi

      cd "$EXE_DIR"
      export WINEDEBUG="-all"

      if [[ "$USE_DESKTOP" -eq 1 ]]; then
        if [[ -z "$DESKTOP_RES" ]]; then
          DETECTED_RES=""
          if command -v niri >/dev/null 2>&1; then
            DETECTED_RES=$(niri msg outputs 2>/dev/null | grep -m1 "Logical size:" | awk '{print $3}' || true)
            if [[ -z "$DETECTED_RES" ]]; then
              DETECTED_RES=$(niri msg outputs 2>/dev/null | grep -m1 "Current mode:" | awk '{print $3}' || true)
            fi
          fi
          if [[ -z "$DETECTED_RES" ]] && command -v xrandr >/dev/null 2>&1 && [[ -n "''${DISPLAY:-}" ]]; then
            DETECTED_RES=$(xrandr 2>/dev/null | grep -m1 '\*' | awk '{print $1}' || true)
          fi
          DESKTOP_RES="''${DETECTED_RES:-1920x1080}"
        fi

        echo "[*] Launching $EXE_NAME in Wine Virtual Desktop (XWays, $DESKTOP_RES)..."
        exec "$WINE_BIN" explorer /desktop="XWays,$DESKTOP_RES" "$EXE_NAME" "''${PASSTHROUGH_ARGS[@]}"
      else
        echo "[*] Launching $EXE_NAME under Wine (XWayland seamless / floating popups)..."
        exec "$WINE_BIN" "$EXE_NAME" "''${PASSTHROUGH_ARGS[@]}"
      fi
    '';
  };
in
{
  options.dfnix.forensics.xways = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Pre-configure Wine, Feitian dongle udev rules, and raw physical disk mapping for portable X-Ways Forensics.";
    };
  };

  config = mkIf config.dfnix.forensics.xways.enable {
    # 1. Wine packages and utilities
    environment.systemPackages = [
      pkgs.wineWow64Packages.stable
      pkgs.winetricks
      pkgs.xhost
      xwaysLauncher
      (pkgs.makeDesktopItem {
        name = "xways";
        desktopName = "X-Ways Forensics (Wine)";
        genericName = "Forensic Analysis Suite";
        comment = "Launch portable X-Ways Forensics with root privileges, dongle support & raw drive mapping";
        exec = "xways";
        icon = "system-search";
        categories = [ "System" "Utility" ];
        keywords = [ "xways" "forensics" "hex" "carving" "evidence" ];
        actions = {
          "virtual-desktop" = {
            name = "Launch in Virtual Desktop";
            exec = "xways --desktop";
          };
        };
      })
    ];

    # 2. Udev rules for Feitian and CodeMeter license dongles
    # Narrowed strictly to hidraw subsystem at 0660 group users (H3)
    services.udev.extraRules = ''
      # Feitian Technologies HID Dongles (096e) and Wibu Systems CodeMeter Dongles (064f)
      # Restricted strictly to the hidraw subsystem to prevent exposing USB mass storage devices.
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="096e", MODE="0660", GROUP="users"
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="064f", MODE="0660", GROUP="users"
    '';
  };
}
