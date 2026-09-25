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
     start-xfce      Launch XFCE desktop (X11 — universal legacy GPU / VM fallback)
     start-niri      Launch Niri Wayland session (or nested window inside XFCE)
     dfnix-session   Start default desktop session (supports: dfnix-session niri | xfce)

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
    # If already running inside X11 or Wayland, do not attempt to start a second X server
    if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
      echo "[-] Error: Graphical session is already active (DISPLAY=''${DISPLAY:-none}, WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-none})."
      echo "    You are already inside an active graphical desktop session."
      exit 1
    fi

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

  startNiri = pkgs.writeShellScriptBin "start-niri" ''
    # If running inside an existing X11/XFCE session, run Niri nested in a window
    if [ -n "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
      echo ">>> Active X11 session detected ($DISPLAY)."
      echo ">>> Launching Niri in a nested Wayland window inside XFCE..."
      exec niri "$@"
    fi

    if [ -n "$WAYLAND_DISPLAY" ]; then
      echo "[-] Error: Wayland session is already active on $WAYLAND_DISPLAY."
      echo "    You are already inside an active graphical desktop session."
      exit 1
    fi

    rm -f /tmp/.dfnix-session-started

    USER_ID="$(id -u)"
    USER_NAME="$(id -un)"
    HOME_DIR="''${HOME:-$(getent passwd "$USER_ID" 2>/dev/null | cut -d: -f6 || echo /home/$USER_NAME)}"

    export NIRI_CONFIG="$HOME_DIR/.config/niri/config.kdl"
    export XDG_CURRENT_DESKTOP="Niri"
    export XDG_SESSION_DESKTOP="niri"
    export XDG_SESSION_TYPE="wayland"
    export NIXOS_OZONE_WL="1"
    export QT_QPA_PLATFORM="wayland;xcb"
    export MOZ_ENABLE_WAYLAND="1"
    export XKB_DEFAULT_LAYOUT="de,us"
    export XKB_DEFAULT_OPTIONS="grp:alt_shift_toggle"

    exec niri-session -l "$@"
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

    TARGET_DESKTOP="''${1:-${config.dfnix.desktop.displayManager.defaultDesktop}}"

    # Session Chooser: Interactive selection at boot
    if [ "$TARGET_DESKTOP" = "chooser" ] || [ "$TARGET_DESKTOP" = "--chooser" ]; then
      if [ -n "$DISPLAY" ]; then
        echo "[-] Running session chooser inside active display $DISPLAY..."
        ${pkgs.dfnix-session-chooser}/bin/dfnix-session-chooser || true
        exit 0
      fi

      while true; do
        rm -f /tmp/.dfnix-chosen-session "/run/user/$USER_ID/dfnix-chosen-session" 2>/dev/null || true

        # Run session chooser on temporary dedicated X11 server
        ${pkgs.xinit}/bin/xinit ${pkgs.dfnix-session-chooser}/bin/dfnix-session-chooser -- :0 vt1 2>/dev/null || true

        CHOSEN_SESSION=""
        if [ -f "/run/user/$USER_ID/dfnix-chosen-session" ]; then
          CHOSEN_SESSION=$(cat "/run/user/$USER_ID/dfnix-chosen-session" | tr -d '[:space:]')
        elif [ -f "/tmp/.dfnix-chosen-session" ]; then
          CHOSEN_SESSION=$(cat "/tmp/.dfnix-chosen-session" | tr -d '[:space:]')
        fi

        if [ "$CHOSEN_SESSION" = "xfce" ]; then
          echo ">>> dfnix: Launching XFCE desktop session..."
          ${startXfce}/bin/start-xfce || true
          echo ">>> XFCE session ended. Returning to session chooser..."
          sleep 1
          continue
        elif [ "$CHOSEN_SESSION" = "niri" ]; then
          echo ">>> dfnix: Launching Niri Wayland session..."
          set +e
          ${startNiri}/bin/start-niri
          NIRI_EXIT=$?
          set -e
          if [ $NIRI_EXIT -ne 0 ]; then
            echo ""
            echo ">>> WARNING: Niri Wayland session exited with code $NIRI_EXIT."
            echo ">>> (If Niri failed to start, verify that 'Accelerate 3D graphics' is enabled in your VM settings)."
            echo ">>> Returning to Session Chooser in 3 seconds..."
            sleep 3
          fi
          continue
        elif [ "$CHOSEN_SESSION" = "console" ]; then
          echo ">>> Dropping to forensic console..."
          clear
          ${dfnixBanner}/bin/dfnix-help
          exec bash --login
        else
          echo ">>> Session Chooser closed. Dropping to forensic console..."
          clear
          ${dfnixBanner}/bin/dfnix-help
          exec bash --login
        fi
      done
    fi

    if [ "$TARGET_DESKTOP" = "xfce" ] || [ "$TARGET_DESKTOP" = "--xfce" ]; then
      if [ -n "$DISPLAY" ]; then
        echo "[-] Error: X server is already active on $DISPLAY."
        echo "    You are already inside an active XFCE session."
        echo "    To launch Niri inside XFCE, run: start-niri (or niri)"
        exit 1
      fi
      echo ">>> dfnix: Launching XFCE desktop session..."
      exec ${startXfce}/bin/start-xfce
    fi

    if [ "$TARGET_DESKTOP" = "niri" ] || [ "$TARGET_DESKTOP" = "--niri" ]; then
      exec ${startNiri}/bin/start-niri
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
      description = "Enable Direct TTY1 session with Niri Wayland, XFCE, and Session Chooser.";
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
      type = types.enum [ "niri" "xfce" "chooser" ];
      default = "niri";
      description = "Default desktop environment to launch ('niri', 'xfce', or 'chooser' for interactive login selection).";
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
      startNiri
      pkgs.dfnix-session-chooser
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
