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
     sudo dfinfo     Forensic System Triage & Fastfetch (Hardware, Disks, Network)
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

    # 1. Wait for GPU KMS DRM card device (prevents early agetty race condition)
    for i in $(seq 1 50); do
      if ls /dev/dri/card* >/dev/null 2>&1; then
        break
      fi
      sleep 0.1
    done

    # 2. Wait for systemd user bus / session initialization
    USER_ID="$(id -u)"
    for i in $(seq 1 30); do
      if [ -S "/run/user/$USER_ID/bus" ] || [ -d "/run/user/$USER_ID/systemd" ]; then
        break
      fi
      sleep 0.1
    done

    HOME_DIR="''${HOME:-/home/nixos}"
    mkdir -p "$HOME_DIR/.config/niri" \
             "$HOME_DIR/.config/noctalia" \
             "$HOME_DIR/.config/kitty" \
             "$HOME_DIR/.local/state/noctalia" \
             "$HOME_DIR/Pictures/Wallpapers"

    # Pre-populate dotfiles from system templates if missing
    if [ ! -f "$HOME_DIR/.config/niri/config.kdl" ] && [ -f /etc/niri/config.kdl ]; then
      cp -f /etc/niri/config.kdl "$HOME_DIR/.config/niri/config.kdl"
    fi
    if [ ! -f "$HOME_DIR/.config/niri/noctalia.kdl" ] && [ -f /etc/niri/noctalia.kdl ]; then
      cp -f /etc/niri/noctalia.kdl "$HOME_DIR/.config/niri/noctalia.kdl"
    fi
    if [ ! -f "$HOME_DIR/.config/noctalia/config.toml" ] && [ -f /etc/xdg/noctalia/config.toml ]; then
      cp -f /etc/xdg/noctalia/config.toml "$HOME_DIR/.config/noctalia/config.toml"
    fi
    if [ ! -f "$HOME_DIR/.local/state/noctalia/settings.toml" ] && [ -f /etc/xdg/noctalia/settings.toml ]; then
      cp -f /etc/xdg/noctalia/settings.toml "$HOME_DIR/.local/state/noctalia/settings.toml"
    fi
    if [ ! -f "$HOME_DIR/.local/state/noctalia/.setup-complete" ]; then
      touch "$HOME_DIR/.local/state/noctalia/.setup-complete"
    fi
    if [ ! -f "$HOME_DIR/.config/noctalia/storage.key" ]; then
      echo "4a6f72656e7369635365637265744b6579313233343536373839616263646566" > "$HOME_DIR/.config/noctalia/storage.key"
      chmod 0600 "$HOME_DIR/.config/noctalia/storage.key"
    fi
    if [ ! -f "$HOME_DIR/.config/kitty/kitty.conf" ] && [ -f /etc/xdg/kitty/kitty.conf ]; then
      cp -f /etc/xdg/kitty/kitty.conf "$HOME_DIR/.config/kitty/kitty.conf"
    fi
    if [ ! -f "$HOME_DIR/.config/starship.toml" ] && [ -f /etc/starship.toml ]; then
      cp -f /etc/starship.toml "$HOME_DIR/.config/starship.toml"
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
    # Use -l flag to prevent upstream niri-session from re-spawning a login shell loop
    niri-session -l
    EXIT_CODE=$?
    set -e

    # If Niri failed (e.g. timeout due to missing 3D GPU acceleration, or crash)
    if [ $EXIT_CODE -ne 0 ]; then
      echo ""
      echo ">>> WARNING: Niri Wayland session failed or timed out (exit code $EXIT_CODE)."
      echo ">>> (Note: Niri requires OpenGL 3.3 / GLES 2.0 3D hardware acceleration)."
      echo ">>> Automatically launching universal XFCE desktop fallback in 2 seconds..."
      sleep 2 || true
      rm -f /tmp/.dfnix-session-started
      exec ${startXfce}/bin/start-xfce
    fi

    clear
    ${dfnixBanner}/bin/dfnix-help
    echo ""
    echo "Niri session exited with code: $EXIT_CODE"
    echo ""
    rm -f /tmp/.dfnix-session-started
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
    # 1. Direct TTY1 autologin without SDDM/LightDM friction
    services.getty.autologinUser = "nixos";

    # Explicitly ensure ALL display managers (SDDM, LightDM, GDM) are completely disabled
    services.xserver.displayManager.lightdm.enable = mkForce false;
    services.displayManager.sddm.enable = mkForce false;
    services.displayManager.gdm.enable = mkForce false;

    # Completely disable GNOME Keyring to eliminate "Choose password for new keyring" prompts
    services.gnome.gnome-keyring.enable = mkForce false;
    security.pam.services.login.enableGnomeKeyring = false;

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
      if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ] && { [ "$(tty 2>/dev/null)" = "/dev/tty1" ] || [ "''${XDG_VTNR:-}" = "1" ]; }; then
        if [ ! -f /tmp/.dfnix-session-started ]; then
          touch /tmp/.dfnix-session-started
          exec dfnix-session
        fi
      fi
    '';
  };
}
