{ config, lib, pkgs, ... }:

with lib;

let
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

    if [[ -z "''${XAUTHORITY:-}" && -f /home/nixos/.Xauthority ]]; then
      export XAUTHORITY="/home/nixos/.Xauthority"
    fi

    # Authorize root on X11 if display is active
    if command -v xhost >/dev/null 2>&1 && [[ -n "''${DISPLAY:-}" ]]; then
      xhost +si:localuser:root >/dev/null 2>&1 || true
    fi

    # 2. Locate X-Ways Executable
    TARGET_EXE="''${1:-}"

    if [[ -z "$TARGET_EXE" ]]; then
      # Search common external media and Desktop locations
      SEARCH_PATHS=(
        "/home/nixos/Desktop"
        "/root/Desktop"
        "/media/target"
        "/media/evidence"
        "/media"
        "/run/media"
      )
      for sp in "''${SEARCH_PATHS[@]}"; do
        if [[ -d "$sp" ]]; then
          FOUND=$(find "$sp" -maxdepth 5 \( -name "xwforensics64.exe" -o -name "xwforensics.exe" \) 2>/dev/null | head -n1 || true)
          if [[ -n "$FOUND" ]]; then
            TARGET_EXE="$FOUND"
            break
          fi
        fi
      done
    fi

    if [[ -z "$TARGET_EXE" || ! -f "$TARGET_EXE" ]]; then
      echo "[!] Error: No X-Ways executable found."
      echo "Usage: xways /path/to/xwforensics64.exe"
      echo "Or ensure your portable X-Ways folder is on Desktop or mounted in /media/target."
      exit 1
    fi

    EXE_DIR=$(dirname "$TARGET_EXE")
    EXE_NAME=$(basename "$TARGET_EXE")
    echo "[*] Found X-Ways executable: $TARGET_EXE"

    # 3. Check Feitian / CodeMeter License Dongle & Ensure Device Permissions
    echo "[*] Checking for connected forensic license dongles..."
    chmod 0666 /dev/hidraw* /dev/usb/hiddev* 2>/dev/null || true

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

    # Initialize Wine prefix cleanly if drive_c or system32 does not exist
    if [[ ! -d "$WINE_DIR/drive_c/windows/system32" ]]; then
      echo "[*] Initializing root Wine prefix (first run, please wait)..."
      rm -rf "$DOS_DIR" 2>/dev/null || true
      WINEDLLOVERRIDES="mscoree,mshtml=" WINEDEBUG="-all" "$WINE_BIN" wineboot -u
      if [[ -x "$WINESERVER_BIN" ]]; then
        "$WINESERVER_BIN" -w 2>/dev/null || true
      fi

      # Configure winebus for direct hidraw hardware dongle support
      echo "[*] Configuring winebus for direct HID hardware access..."
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winebus" /v DisableHidraw /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
      WINEDEBUG="-all" "$WINE_BIN" reg add "HKLM\\System\\CurrentControlSet\\Services\\winebus" /v "Enable SDL" /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
      if [[ -x "$WINESERVER_BIN" ]]; then
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
    echo "[*] Launching $EXE_NAME under Wine (as root)..."
    cd "$EXE_DIR"
    export WINEDEBUG="-all"
    exec "$WINE_BIN" "$EXE_NAME" "$@"
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
