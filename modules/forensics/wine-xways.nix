{ config, lib, pkgs, ... }:

with lib;

let
  # Dedicated X-Ways launcher and Wine disk-mapper helper
  xwaysLauncher = pkgs.writeShellScriptBin "xways" ''
    set -euo pipefail

    echo "=== X-Ways Forensics Wine Environment Initializer ==="

    # 1. Locate X-Ways Executable
    TARGET_EXE="''${1:-}"

    if [[ -z "$TARGET_EXE" ]]; then
      # Search common external media and Desktop locations
      SEARCH_PATHS=(
        "$HOME/Desktop"
        "/media/target"
        "/media/evidence"
        "/run/media"
      )
      for sp in "''${SEARCH_PATHS[@]}"; do
        if [[ -d "$sp" ]]; then
          FOUND=$(find "$sp" -maxdepth 4 -name "xwforensics64.exe" -o -name "xwforensics.exe" 2>/dev/null | head -n1 || true)
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

    # 2. Check Feitian / CodeMeter License Dongle
    echo "[*] Checking for connected forensic license dongles..."
    if compgen -G "/dev/hidraw*" >/dev/null 2>&1; then
      if grep -q "096e" /sys/class/hidraw/*/device/uevent 2>/dev/null; then
        echo "[✓] Feitian HID security dongle detected (096e)."
      elif grep -q "064f" /sys/class/hidraw/*/device/uevent 2>/dev/null; then
        echo "[✓] CodeMeter security dongle detected (064f)."
      else
        echo "[*] Note: Hardware dongle not detected on HID raw interface."
      fi
    else
      echo "[*] Note: No HID raw devices detected."
    fi

    # 3. Setup Wine Prefix and DOS Devices
    WINE_DIR="$HOME/.wine"
    DOS_DIR="$WINE_DIR/dosdevices"

    WINE_BIN="${pkgs.wineWow64Packages.stable}/bin/wine"
    if [ ! -x "$WINE_BIN" ] && [ -x "${pkgs.wineWow64Packages.stable}/bin/wine64" ]; then
      WINE_BIN="${pkgs.wineWow64Packages.stable}/bin/wine64"
    fi
    WINESERVER_BIN="${pkgs.wineWow64Packages.stable}/bin/wineserver"

    # Initialize Wine prefix cleanly if drive_c or system32 does not exist
    if [[ ! -d "$WINE_DIR/drive_c/windows/system32" ]]; then
      echo "[*] Initializing Wine prefix (first run, please wait)..."
      rm -rf "$DOS_DIR" 2>/dev/null || true
      WINEDLLOVERRIDES="mscoree,mshtml=" WINEDEBUG="-all" "$WINE_BIN" wineboot -u
      if [[ -x "$WINESERVER_BIN" ]]; then
        "$WINESERVER_BIN" -w 2>/dev/null || true
      fi
    fi

    mkdir -p "$DOS_DIR"

    # Ensure C: and Z: DOS drives are always linked properly
    ln -sfn ../drive_c "$DOS_DIR/c:"
    ln -sfn / "$DOS_DIR/z:"

    # Map /media and /run/media to dedicated drive letters for convenience
    if [[ -d /media ]]; then
      ln -sfn /media "$DOS_DIR/m:"
    fi
    if [[ -d /run/media ]]; then
      ln -sfn /run/media "$DOS_DIR/r:"
    fi

    # Map physical block devices for raw physical drive inspection
    echo "[*] Mapping physical drives into Wine dosdevices for raw forensics inspection..."
    letters=(d e f g h i j k l n o p q s t u v w x y)
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

    # 4. Launch X-Ways under Wine
    echo "[*] Launching $EXE_NAME under Wine..."
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
      xwaysLauncher
      (pkgs.makeDesktopItem {
        name = "xways";
        desktopName = "X-Ways Forensics (Wine)";
        genericName = "Forensic Analysis Suite";
        comment = "Launch portable X-Ways Forensics from ingestion drive with Feitian dongle & raw disk mapping";
        exec = "xways";
        icon = "system-search";
        categories = [ "System" "Utility" ];
        keywords = [ "xways" "forensics" "hex" "carving" "evidence" ];
      })
    ];

    # 2. Udev rules for Feitian and CodeMeter license dongles
    services.udev.extraRules = ''
      # Feitian Technologies HID Dongle (e.g. 096e:0006 for X-Ways)
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="096e", MODE="0666", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="096e", MODE="0666", TAG+="uaccess"

      # Wibu Systems CodeMeter Dongle
      SUBSYSTEM=="usb", ATTRS{idVendor}=="064f", MODE="0666", TAG+="uaccess"
    '';

    # 3. Ensure live user has raw disk access privileges
    users.users.nixos.extraGroups = [ "disk" ];
  };
}
