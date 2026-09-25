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
     dfnix-guide     Forensic Quick Start Guide & Keybinding Cheat Sheet (F1)
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

    # Set clean X11 / XFCE environment and neutralize Wayland variables in shell
    export XDG_CURRENT_DESKTOP="XFCE"
    export XDG_SESSION_DESKTOP="xfce"
    export XDG_SESSION_TYPE="x11"
    export QT_QPA_PLATFORM="xcb"
    export GDK_BACKEND="x11"
    unset NIXOS_OZONE_WL
    unset MOZ_ENABLE_WAYLAND
    unset WAYLAND_DISPLAY
    unset NIRI_SOCKET

    # D-Bus daemon cannot delete variables once set, so explicitly overwrite stale Wayland settings with empty/disabled values
    if command -v dbus-update-activation-environment >/dev/null 2>&1; then
      dbus-update-activation-environment --systemd \
        XDG_CURRENT_DESKTOP="XFCE" \
        XDG_SESSION_DESKTOP="xfce" \
        XDG_SESSION_TYPE="x11" \
        QT_QPA_PLATFORM="xcb" \
        GDK_BACKEND="x11" \
        NIXOS_OZONE_WL="" \
        MOZ_ENABLE_WAYLAND="0" \
        WAYLAND_DISPLAY="" \
        NIRI_SOCKET="" 2>/dev/null || true
    fi

    # Reset systemd user environment (systemd supports unsetting variables cleanly)
    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user unset-environment NIXOS_OZONE_WL MOZ_ENABLE_WAYLAND WAYLAND_DISPLAY NIRI_SOCKET 2>/dev/null || true
      systemctl --user set-environment XDG_CURRENT_DESKTOP="XFCE" XDG_SESSION_DESKTOP="xfce" XDG_SESSION_TYPE="x11" QT_QPA_PLATFORM="xcb" GDK_BACKEND="x11" 2>/dev/null || true
    fi

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

    USER_ID="$(id -u)"
    USER_NAME="$(id -un)"
    HOME_DIR="''${HOME:-$(getent passwd "$USER_ID" 2>/dev/null | cut -d: -f6 || echo /home/$USER_NAME)}"
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
    # Static dummy seed key for live ISO Noctalia UI settings (suppresses keyring popups on read-only media)
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
    if [ -d /etc/xdg/dfnix/wallpapers ]; then
      cp -rn /etc/xdg/dfnix/wallpapers/* "$HOME_DIR/Pictures/Wallpapers/" 2>/dev/null || true
    fi

    export XKB_DEFAULT_LAYOUT="de,us"
    export XKB_DEFAULT_OPTIONS="grp:alt_shift_toggle"

    DEFAULT_DESKTOP="${config.dfnix.desktop.displayManager.defaultDesktop}"
    if [ "$DEFAULT_DESKTOP" = "xfce" ]; then
      echo ">>> dfnix: Launching XFCE desktop session..."
      exec ${startXfce}/bin/start-xfce
    fi

    echo ">>> dfnix: Starting Niri Wayland session..."
    export NIRI_CONFIG="$HOME_DIR/.config/niri/config.kdl"
    export XDG_CURRENT_DESKTOP="Niri"
    export XDG_SESSION_DESKTOP="niri"
    export XDG_SESSION_TYPE="wayland"
    export NIXOS_OZONE_WL="1"
    export QT_QPA_PLATFORM="wayland;xcb"
    export MOZ_ENABLE_WAYLAND="1"
    set +e
    # Use -l flag to prevent upstream niri-session from re-spawning a login shell loop
    niri-session -l
    EXIT_CODE=$?

    # Check whether niri-session or the underlying niri.service failed
    NIRI_FAILED=0
    if [ $EXIT_CODE -ne 0 ]; then
      NIRI_FAILED=1
    elif systemctl --user is-failed -q niri.service 2>/dev/null; then
      NIRI_FAILED=1
    else
      NIRI_RESULT=$(systemctl --user show -p Result --value niri.service 2>/dev/null || true)
      if [ -n "$NIRI_RESULT" ] && [ "$NIRI_RESULT" != "success" ]; then
        NIRI_FAILED=1
      fi
    fi
    set -e

    # If Niri failed (e.g. missing 3D GPU acceleration, crash, or startup timeout)
    if [ $NIRI_FAILED -ne 0 ]; then
      echo ""
      echo ">>> WARNING: Niri Wayland session failed (exit code $EXIT_CODE, result: ''${NIRI_RESULT:-failed})."
      echo ">>> (Note: Niri requires OpenGL 3.3 / GLES 2.0 3D hardware acceleration)."
      echo ">>> Automatically launching universal XFCE desktop fallback in 2 seconds..."
      sleep 2 || true
      exec ${startXfce}/bin/start-xfce
    fi

    clear
    ${dfnixBanner}/bin/dfnix-help
    echo ""
    echo "Niri session exited normally."
    echo ""
    # Note: Retain /tmp/.dfnix-session-started so returning to the console prompt
    # does NOT re-launch Niri or enter an infinite loop.
    exec bash --login
  '';
in
{
  options.dfnix.desktop.displayManager = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Direct TTY1 session with Niri Wayland and XFCE fallback.";
    };
    autologin = mkOption {
      type = types.bool;
      default = false;
      description = "Enable automatic login on TTY1.";
    };
    autologinUser = mkOption {
      type = types.str;
      default = "nixos";
      description = "User account to automatically log in on TTY1.";
    };
    defaultDesktop = mkOption {
      type = types.enum [ "niri" "xfce" ];
      default = "niri";
      description = "Default desktop environment to launch ('niri' with auto-fallback to XFCE, or 'xfce' directly).";
    };
  };

  config = mkIf config.dfnix.desktop.displayManager.enable {
    # 1. Direct TTY1 autologin when enabled
    services.getty.autologinUser = mkIf config.dfnix.desktop.displayManager.autologin config.dfnix.desktop.displayManager.autologinUser;

    # Enable X server and startx support so startxfce4 receives NixOS X server arguments and /etc/X11/xinit/xserverrc
    services.xserver.enable = true;
    services.xserver.displayManager.startx.enable = true;

    # Explicitly ensure display managers (SDDM, LightDM, GDM) are disabled when direct TTY1 autologin is requested
    services.xserver.displayManager.lightdm.enable = mkIf config.dfnix.desktop.displayManager.autologin (mkForce false);
    services.displayManager.sddm.enable = mkIf config.dfnix.desktop.displayManager.autologin (mkForce false);
    services.displayManager.gdm.enable = mkIf config.dfnix.desktop.displayManager.autologin (mkForce false);

    # Completely disable GNOME Keyring on direct autologin live sessions to eliminate popups
    services.gnome.gnome-keyring.enable = mkIf config.dfnix.desktop.displayManager.autologin (mkForce false);
    security.pam.services.login.enableGnomeKeyring = mkIf config.dfnix.desktop.displayManager.autologin false;

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
