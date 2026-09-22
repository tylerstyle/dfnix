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

        def rva_to_offset(rva):
            for i in range(num_sections):
                sec = data[sec_offset + i*40 : sec_offset + (i+1)*40]
                vsize, va, rsize, rptr = struct.unpack_from("<IIII", sec, 8)
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

        target_offset = None
        for i in range(num_names):
            name_rva = struct.unpack_from("<I", data, names_off + i*4)[0]
            name_off = rva_to_offset(name_rva)
            fn_name = data[name_off:data.find(b"\x00", name_off)].decode("ascii")
            if fn_name == "HidD_FlushQueue":
                ord_val = struct.unpack_from("<H", data, ords_off + i*2)[0]
                func_rva = struct.unpack_from("<I", data, funcs_off + ord_val*4)[0]
                target_offset = rva_to_offset(func_rva)
                break

        if target_offset is None:
            sys.exit(f"HidD_FlushQueue not found in {src_path}")

        # Patch: mov $1, %eax; ret (or ret $4 in 32-bit stdcall)
        if is_64:
            patch = b"\xb8\x01\x00\x00\x00\xc3"
        else:
            patch = b"\xb8\x01\x00\x00\x00\xc2\x04\x00"
        data[target_offset:target_offset + len(patch)] = patch
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
  # Feitian/CodeMeter dongle support, and raw physical disk mapping.
  xwaysLauncher = pkgs.writeShellScriptBin "xways" ''
    set -euo pipefail

    echo "=== X-Ways Forensics Wine Environment Initializer ==="

    # 0. Ensure root privileges for raw physical drive access, dongle hardware access,
    # and write access to targets mounted by dfmount (which are owned by root:root).
    if [[ $EUID -ne 0 ]]; then
      USER_WAYLAND="''${WAYLAND_DISPLAY:-}"
      USER_XDG="''${XDG_RUNTIME_DIR:-/run/user/$UID}"
      USER_DISP="''${DISPLAY:-}"
      USER_XAUTH="''${XAUTHORITY:-$HOME/.Xauthority}"

      echo "[*] Elevating to root for raw block device, dongle, and target write access..."
      exec sudo \
        WAYLAND_DISPLAY="$USER_WAYLAND" \
        XDG_RUNTIME_DIR="$USER_XDG" \
        DISPLAY="$USER_DISP" \
        XAUTHORITY="$USER_XAUTH" \
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
    mount --bind "${patchedWineHid64}" "${pkgs.wineWow64Packages.stable}/lib/wine/x86_64-windows/hid.dll"
    mount --bind "${patchedWineHid32}" "${pkgs.wineWow64Packages.stable}/lib/wine/i386-windows/hid.dll"

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
              export XDG_RUNTIME_DIR="$u_dir"
              export WAYLAND_DISPLAY="$(basename "$sock")"
              break 2
            fi
          done
        fi
      done
    fi

    if [[ -z "''${DISPLAY:-}" && -e /tmp/.X11-unix/X0 ]]; then
      export DISPLAY=":0"
    fi

    if [[ -z "''${XAUTHORITY:-}" && -f "''${HOME:-/home/nixos}/.Xauthority" ]]; then
      export XAUTHORITY="''${HOME:-/home/nixos}/.Xauthority"
    fi

    # Authorize root on X11 if display is active
    if command -v xhost >/dev/null 2>&1 && [[ -n "''${DISPLAY:-}" ]]; then
      xhost +si:localuser:root >/dev/null 2>&1 || true
    fi

    # 2. Parse Options and Locate X-Ways Executable
    USE_DESKTOP="''${XWAYS_DESKTOP:-0}"
    DESKTOP_RES="''${XWAYS_DESKTOP_RES:-}"
    TARGET_ARG=""
    PASSTHROUGH_ARGS=()

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -d|--desktop)
          USE_DESKTOP=1
          shift
          ;;
        -r|--res|--resolution)
          DESKTOP_RES="$2"
          shift 2
          ;;
        --desktop=*)
          USE_DESKTOP=1
          DESKTOP_RES="''${1#*=}"
          shift
          ;;
        -h|--help)
          echo "Usage: xways [options] [/path/to/portable/folder or .exe] [xways args...]"
          echo ""
          echo "Options:"
          echo "  -d, --desktop                Run in Wine Virtual Desktop container (isolates all popups/dialogs)"
          echo "  -r, --res, --resolution WxH  Set virtual desktop resolution (e.g. 1920x1080). Auto-detects display if omitted"
          echo "  -h, --help                   Show this help message"
          echo ""
          echo "Environment Variables:"
          echo "  XWAYS_DESKTOP=1              Default to virtual desktop mode"
          echo "  XWAYS_DESKTOP_RES=WxH        Default resolution for virtual desktop"
          exit 0
          ;;
        *)
          if [[ -z "$TARGET_ARG" && ( -d "$1" || -f "$1" ) ]]; then
            TARGET_ARG="$1"
          else
            PASSTHROUGH_ARGS+=("$1")
          fi
          shift
          ;;
      esac
    done

    TARGET_EXE="$TARGET_ARG"

    # If target argument is a directory, search inside it first
    if [[ -n "$TARGET_EXE" && -d "$TARGET_EXE" ]]; then
      SEARCH_DIR="$TARGET_EXE"
      TARGET_EXE=""
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
    fi

    if [[ -z "$TARGET_EXE" ]]; then
      # Search common external media and Desktop locations
      SEARCH_PATHS=(
        "/media/target"
        "/media/evidence"
        "/media"
        "/run/media"
        "''${HOME:-/home/nixos}/Desktop"
        "/root/Desktop"
      )

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
      echo "[!] Error: No X-Ways executable found."
      echo "Usage: xways [options] /path/to/xwforensics64.exe"
      echo "Or ensure your portable X-Ways folder is on Desktop or mounted in /media/target."
      exit 1
    fi

    EXE_DIR=$(dirname "$TARGET_EXE")
    EXE_NAME=$(basename "$TARGET_EXE")
    echo "[*] Found X-Ways executable: $TARGET_EXE"

    # 3. Check Feitian / CodeMeter License Dongle & Ensure Device Permissions
    echo "[*] Checking for connected forensic license dongles..."
    chmod 0666 /dev/hidraw* /dev/usb/hiddev* /dev/bus/usb/*/* 2>/dev/null || true

    DONGLE_FOUND=0
    if compgen -G "/dev/hidraw*" >/dev/null 2>&1; then
      if grep -q "096e" /sys/class/hidraw/*/device/uevent 2>/dev/null; then
        echo "[✓] Feitian HID security dongle detected (096e)."
        DONGLE_FOUND=1
      elif grep -q "064f" /sys/class/hidraw/*/device/uevent 2>/dev/null; then
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
      echo "[*] Initializing root Wine prefix with Plug-and-Play bus devices (please wait)..."
      rm -rf "$DOS_DIR" 2>/dev/null || true
      WINEDLLOVERRIDES="mscoree,mshtml=" WINEDEBUG="-all" "$WINE_BIN" wineboot -i
      if [[ -x "$WINESERVER_BIN" ]]; then
        "$WINESERVER_BIN" -w 2>/dev/null || true
      fi

      # Explicitly register and configure winebus kernel service for hardware dongles
      echo "[*] Configuring winebus and direct HID raw device access..."
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winebus" /v ImagePath /t REG_EXPAND_SZ /d "system32\\drivers\\winebus.sys" /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winebus" /v Type /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winebus" /v Start /t REG_DWORD /d 2 /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winebus" /v ErrorControl /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winebus" /v Group /t REG_SZ /d "WinePlugPlay" /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winebus" /v DisableHidraw /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winebus" /v "Enable SDL" /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true

      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winehid" /v ImagePath /t REG_EXPAND_SZ /d "system32\\drivers\\winehid.sys" /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winehid" /v Type /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winehid" /v Start /t REG_DWORD /d 3 /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winehid" /v ErrorControl /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winehid" /v Group /t REG_SZ /d "WinePlugPlay" /f >/dev/null 2>&1 || true

      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Enum\\ROOT\\WINE\\WINEBUS" /v Class /t REG_SZ /d "System" /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Enum\\ROOT\\WINE\\WINEBUS" /v ClassGUID /t REG_SZ /d "{4D36E97D-E325-11CE-BFC1-08002BE10318}" /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Enum\\ROOT\\WINE\\WINEBUS" /v DeviceDesc /t REG_SZ /d "Wine HID bus driver" /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Enum\\ROOT\\WINE\\WINEBUS" /v HardwareId /t REG_MULTI_SZ /d "root\\winebus\0" /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Enum\\ROOT\\WINE\\WINEBUS" /v Service /t REG_SZ /d "winebus" /f >/dev/null 2>&1 || true

      if [[ -x "$WINESERVER_BIN" ]]; then
        "$WINESERVER_BIN" -k 2>/dev/null || true
        "$WINESERVER_BIN" -w 2>/dev/null || true
      fi
    fi

    mkdir -p "$DOS_DIR"

    # Ensure C: and Z: DOS drives are always linked properly
    ln -sfn ../drive_c "$DOS_DIR/c:"
    ln -sfn / "$DOS_DIR/z:"

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

    # Map physical block devices for raw physical drive inspection
    # Use letters that avoid collisions with c, e, m, r, t, z
    echo "[*] Mapping physical drives into Wine dosdevices for raw forensics inspection..."
    letters=(d f g h i j k l n o p q s u v w x y)
    idx=0

    for dev in $(lsblk -dpno NAME 2>/dev/null | grep -E "sd[a-z]$|nvme[0-9]+n[0-9]+$|mmcblk[0-9]+$" | sort); do
      if [[ $idx -lt ''${#letters[@]} ]]; then
        letter="''${letters[$idx]}"
        # Wine raw device mapping syntax: letter:: -> /dev/sdX
        target_link="$DOS_DIR/''${letter}::"
        rm -f "$target_link"
        ln -s "$dev" "$target_link"
        echo "    Mapped raw drive $dev -> ''${letter}::"
        idx=$((idx + 1))
      fi
    done

    # 5. Launch X-Ways under Wine
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
      echo "[*] Launching $EXE_NAME under Wine (native Wayland / floating popups)..."
      exec "$WINE_BIN" "$EXE_NAME" "''${PASSTHROUGH_ARGS[@]}"
    fi
  '';
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
      (pkgs.makeDesktopItem {
        name = "xways-desktop";
        desktopName = "X-Ways Forensics (Virtual Desktop)";
        genericName = "Forensic Analysis Suite (Virtual Desktop)";
        comment = "Launch portable X-Ways Forensics inside an emulated Windows desktop container (isolated popups)";
        exec = "xways --desktop";
        icon = "system-search";
        categories = [ "System" "Utility" ];
        keywords = [ "xways" "forensics" "desktop" "wine" ];
      })
    ];

    # 2. Udev rules for Feitian and CodeMeter license dongles
    services.udev.extraRules = ''
      # Feitian Technologies HID Dongles (e.g. 096e:0006 for X-Ways)
      KERNEL=="hidraw*", ATTRS{idVendor}=="096e", MODE="0666", GROUP="users"
      KERNEL=="hiddev*", ATTRS{idVendor}=="096e", MODE="0666", GROUP="users"
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="096e", MODE="0666", GROUP="users"
      SUBSYSTEM=="usbmisc", ATTRS{idVendor}=="096e", MODE="0666", GROUP="users"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="096e", MODE="0666", GROUP="users"
      ENV{ID_VENDOR_ID}=="096e", MODE="0666", GROUP="users"

      # Wibu Systems CodeMeter Dongles (064f)
      KERNEL=="hidraw*", ATTRS{idVendor}=="064f", MODE="0666", GROUP="users"
      KERNEL=="hiddev*", ATTRS{idVendor}=="064f", MODE="0666", GROUP="users"
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="064f", MODE="0666", GROUP="users"
      SUBSYSTEM=="usbmisc", ATTRS{idVendor}=="064f", MODE="0666", GROUP="users"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="064f", MODE="0666", GROUP="users"
      ENV{ID_VENDOR_ID}=="064f", MODE="0666", GROUP="users"
    '';

    # 3. Ensure live user has raw disk access privileges
    users.users.nixos.extraGroups = [ "disk" ];
  };
}
