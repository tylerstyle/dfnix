{ config, lib, pkgs, ... }:

with lib;

{
  options.dfnix.desktop.niri = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Niri Wayland scrollable-tiling compositor with Noctalia shell.";
    };
  };

  config = mkIf config.dfnix.desktop.niri.enable {
    # 1. Enable Niri compositor
    programs.niri.enable = true;
    programs.dconf.enable = true;

    # 2. Wayland session environment variables
    environment.sessionVariables = {
      NIRI_CONFIG = "/home/nixos/.config/niri/config.kdl";
      NIXOS_OZONE_WL = "1";
      QT_QPA_PLATFORM = "wayland;xcb";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      MOZ_ENABLE_WAYLAND = "1";
      XDG_CURRENT_DESKTOP = "Niri";
      XKB_DEFAULT_LAYOUT = "de,us";
      XKB_DEFAULT_OPTIONS = "grp:alt_shift_toggle";
    };

    # Explicitly ensure systemd user service for Niri receives NIRI_CONFIG
    systemd.user.services.niri = {
      environment = {
        NIRI_CONFIG = "/home/nixos/.config/niri/config.kdl";
        XDG_CURRENT_DESKTOP = "Niri";
        NIXOS_OZONE_WL = "1";
        QT_QPA_PLATFORM = "wayland;xcb";
        MOZ_ENABLE_WAYLAND = "1";
        XKB_DEFAULT_LAYOUT = "de,us";
        XKB_DEFAULT_OPTIONS = "grp:alt_shift_toggle";
      };
      serviceConfig = {
        TimeoutStartSec = "10s";
      };
    };

    # Completely disable GNOME Keyring to prevent "Choose password for new keyring" dialogs on live ISO
    services.gnome.gnome-keyring.enable = mkForce false;
    security.pam.services.login.enableGnomeKeyring = false;

    # 3. System packages required for Niri + Noctalia desktop
    environment.systemPackages = with pkgs; [
      noctalia
      kitty
      kdePackages.dolphin
      swaybg
      wl-clipboard
      cliphist
      brightnessctl
      pavucontrol
      networkmanagerapplet
      libnotify
      xinit
    ];

    # 4. System-wide configuration fallbacks (checks /etc/niri and /etc/xdg)
    environment.etc = {
      # Hardcoded system search path in niri binary (/etc/niri/config.kdl)
      "niri/config.kdl".source = ../../configs/niri/config.kdl;
      "niri/noctalia.kdl".source = ../../configs/niri/noctalia.kdl;

      # XDG standard search paths
      "xdg/niri/config.kdl".source = ../../configs/niri/config.kdl;
      "xdg/niri/noctalia.kdl".source = ../../configs/niri/noctalia.kdl;
      "xdg/noctalia/config.toml".source = ../../configs/noctalia/config.toml;
      "xdg/noctalia/settings.toml".source = ../../configs/noctalia/settings.toml;
      "xdg/kitty/kitty.conf".source = ../../configs/kitty/kitty.conf;
      "xdg/dfnix/wallpaper.png".source = ../../configs/assets/wallpaper.png;
      "starship.toml".source = ../../configs/starship/starship.toml;
    };

    # 5. Pre-populate live examiner home directory at boot before login
    systemd.tmpfiles.rules = [
      "d /home/nixos 0755 nixos users -"
      "d /home/nixos/.config 0755 nixos users -"
      "d /home/nixos/.config/niri 0755 nixos users -"
      "d /home/nixos/.config/noctalia 0755 nixos users -"
      "d /home/nixos/.config/kitty 0755 nixos users -"
      "d /home/nixos/.local 0755 nixos users -"
      "d /home/nixos/.local/state 0755 nixos users -"
      "d /home/nixos/.local/state/noctalia 0755 nixos users -"
      "d /home/nixos/Pictures 0755 nixos users -"
      "d /home/nixos/Pictures/Wallpapers 0755 nixos users -"

      # Niri configs
      "C /home/nixos/.config/niri/config.kdl 0644 nixos users - ${../../configs/niri/config.kdl}"
      "C /home/nixos/.config/niri/noctalia.kdl 0644 nixos users - ${../../configs/niri/noctalia.kdl}"

      # Noctalia configs & state (prevents first-run setup wizard & gnome-keyring prompt)
      "C /home/nixos/.config/noctalia/config.toml 0644 nixos users - ${../../configs/noctalia/config.toml}"
      "C /home/nixos/.local/state/noctalia/settings.toml 0644 nixos users - ${../../configs/noctalia/settings.toml}"
      "f /home/nixos/.local/state/noctalia/.setup-complete 0644 nixos users - -"
      "f /home/nixos/.config/noctalia/storage.key 0600 nixos users - 4a6f72656e7369635365637265744b6579313233343536373839616263646566"

      # Kitty & Starship configs
      "C /home/nixos/.config/kitty/kitty.conf 0644 nixos users - ${../../configs/kitty/kitty.conf}"
      "C /home/nixos/.config/starship.toml 0644 nixos users - ${../../configs/starship/starship.toml}"

      # Wallpaper
      "C /home/nixos/Pictures/DF_K-BG02.png 0644 nixos users - ${../../configs/assets/wallpaper.png}"
      "C /home/nixos/Pictures/Wallpapers/DF_K-BG02.png 0644 nixos users - ${../../configs/assets/wallpaper.png}"
    ];

    # 6. Fallback activation script for skel and persistent users
    system.activationScripts.dfnixNiriConfig = ''
      mkdir -p /etc/skel/.config/niri /etc/skel/.config/noctalia /etc/skel/.config/kitty /etc/skel/.local/state/noctalia /etc/skel/Pictures/Wallpapers
      cp -f ${../../configs/niri/config.kdl} /etc/skel/.config/niri/config.kdl 2>/dev/null || true
      cp -f ${../../configs/niri/noctalia.kdl} /etc/skel/.config/niri/noctalia.kdl 2>/dev/null || true
      cp -f ${../../configs/noctalia/config.toml} /etc/skel/.config/noctalia/config.toml 2>/dev/null || true
      cp -f ${../../configs/noctalia/settings.toml} /etc/skel/.local/state/noctalia/settings.toml 2>/dev/null || true
      touch /etc/skel/.local/state/noctalia/.setup-complete 2>/dev/null || true
      echo "4a6f72656e7369635365637265744b6579313233343536373839616263646566" > /etc/skel/.config/noctalia/storage.key 2>/dev/null || true
      chmod 0600 /etc/skel/.config/noctalia/storage.key 2>/dev/null || true
      cp -f ${../../configs/kitty/kitty.conf} /etc/skel/.config/kitty/kitty.conf 2>/dev/null || true
      cp -f ${../../configs/starship/starship.toml} /etc/skel/.config/starship.toml 2>/dev/null || true
      cp -f ${../../configs/assets/wallpaper.png} /etc/skel/Pictures/DF_K-BG02.png 2>/dev/null || true
      cp -f ${../../configs/assets/wallpaper.png} /etc/skel/Pictures/Wallpapers/DF_K-BG02.png 2>/dev/null || true
    '';
  };
}
