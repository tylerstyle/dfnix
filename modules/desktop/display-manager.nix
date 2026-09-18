{ config, lib, pkgs, ... }:

with lib;

let
  dfnixBanner = pkgs.writeShellScriptBin "dfnix-help" ''
    cat << 'EOF'
  ╔══════════════════════════════════════════════════════════════════════════════╗
  ║                 dfnix — Forensic Live Acquisition Environment                ║
  ╚══════════════════════════════════════════════════════════════════════════════╝

   Graphical session ended or dropped to console.

   [DESKTOP ENVIRONMENTS]
     startxfce4      Launch XFCE desktop (X11 — universal legacy GPU fallback)
     dfnix-session   Restart Niri Wayland compositor with Noctalia shell

   [FORENSIC TUIs (Direct CLI)]
     sudo dfdisk     Forensic Disk Imaging & ddrescue TUI (RAW, E01, verification)
     sudo dfmount    Forensic Storage Manager (hardware/software write-blocking)
     sudo dfnet      Forensic Network Operations (MAC spoof, SMB/NFS share mount)
     sudo nmtui      NetworkManager Connection Manager

   [SYSTEM COMMANDS]
     sudo poweroff   Safely sync disks and power off the machine
     sudo reboot     Reboot system
     dfnix-help      Redisplay this information menu
  ══════════════════════════════════════════════════════════════════════════════
EOF
  '';

  startXfce = pkgs.writeShellScriptBin "start-xfce" ''
    rm -f /tmp/.dfnix-session-started
    exec ${pkgs.xfce4-session}/bin/startxfce4 "$@"
  '';

  dfnixSession = pkgs.writeShellScriptBin "dfnix-session" ''
    set -e

    HOME_DIR="''${HOME:-/home/nixos}"
    mkdir -p "$HOME_DIR/.config/niri" "$HOME_DIR/.config/noctalia" "$HOME_DIR/Pictures/Wallpapers"

    # Pre-populate dotfiles from system templates if missing
    if [ ! -f "$HOME_DIR/.config/niri/config.kdl" ] && [ -f /etc/xdg/niri/config.kdl ]; then
      cp -f /etc/xdg/niri/config.kdl "$HOME_DIR/.config/niri/config.kdl"
    fi
    if [ ! -f "$HOME_DIR/.config/niri/noctalia.kdl" ] && [ -f /etc/xdg/niri/noctalia.kdl ]; then
      cp -f /etc/xdg/niri/noctalia.kdl "$HOME_DIR/.config/niri/noctalia.kdl"
    fi
    if [ ! -f "$HOME_DIR/.config/noctalia/settings.json" ] && [ -f /etc/xdg/noctalia/settings.json ]; then
      cp -f /etc/xdg/noctalia/settings.json "$HOME_DIR/.config/noctalia/settings.json"
    fi
    if [ ! -f "$HOME_DIR/.config/noctalia/plugins.json" ] && [ -f /etc/xdg/noctalia/plugins.json ]; then
      cp -f /etc/xdg/noctalia/plugins.json "$HOME_DIR/.config/noctalia/plugins.json"
    fi
    if [ ! -f "$HOME_DIR/Pictures/DF_K-BG02.png" ] && [ -f /etc/xdg/dfnix/wallpaper.png ]; then
      cp -f /etc/xdg/dfnix/wallpaper.png "$HOME_DIR/Pictures/DF_K-BG02.png"
      cp -f /etc/xdg/dfnix/wallpaper.png "$HOME_DIR/Pictures/Wallpapers/DF_K-BG02.png"
    fi

    export NIRI_CONFIG="$HOME_DIR/.config/niri/config.kdl"
    export XDG_CURRENT_DESKTOP="Niri"
    export NIXOS_OZONE_WL="1"
    export QT_QPA_PLATFORM="wayland;xcb"
    export MOZ_ENABLE_WAYLAND="1"
    export XKB_DEFAULT_LAYOUT="de,us"
    export XKB_DEFAULT_OPTIONS="grp:alt_shift_toggle"

    echo ">>> dfnix: Starting Niri Wayland session..."
    set +e
    niri-session
    EXIT_CODE=$?
    set -e

    clear
    ${dfnixBanner}/bin/dfnix-help
    echo ""
    echo "Niri session exited with code: $EXIT_CODE"
    echo ""
    exec bash --login
  '';
in
{
  options.dfnix.desktop.displayManager = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Direct TTY1 Autologin with Niri Wayland and XFCE fallback.";
    };
  };

  config = mkIf config.dfnix.desktop.displayManager.enable {
    # 1. Direct TTY1 autologin without SDDM friction
    services.getty.autologinUser = "nixos";

    # Explicitly ensure SDDM is disabled
    services.displayManager.sddm.enable = false;

    # 2. Live ISO user privileges & passwordless login/sudo
    users.users.nixos = {
      isNormalUser = true;
      extraGroups = [ "wheel" "disk" "storage" "networkmanager" "video" "audio" "input" ];
      description = "Forensic Field Examiner";
      initialHashedPassword = "";
    };
    users.users.root.initialHashedPassword = "";
    security.sudo.wheelNeedsPassword = false;

    # 3. Session and helper scripts
    environment.systemPackages = [
      dfnixSession
      dfnixBanner
      startXfce
    ];

    # 4. Auto-launch Niri on TTY1 login
    environment.loginShellInit = ''
      if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
        if [ ! -f /tmp/.dfnix-session-started ]; then
          touch /tmp/.dfnix-session-started
          exec dfnix-session
        fi
      fi
    '';
  };
}
