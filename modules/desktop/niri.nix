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
    systemd.user.services.niri.environment = {
      NIRI_CONFIG = "/home/nixos/.config/niri/config.kdl";
      XDG_CURRENT_DESKTOP = "Niri";
      NIXOS_OZONE_WL = "1";
      QT_QPA_PLATFORM = "wayland;xcb";
      MOZ_ENABLE_WAYLAND = "1";
      XKB_DEFAULT_LAYOUT = "de,us";
      XKB_DEFAULT_OPTIONS = "grp:alt_shift_toggle";
    };

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
      "xdg/noctalia/settings.json".source = ../../configs/noctalia/settings.json;
      "xdg/noctalia/plugins.json".text = ''{"version":2,"states":{},"sources":[]}'';
      "xdg/dfnix/wallpaper.png".source = ../../configs/assets/wallpaper.png;
    };

    # 5. Pre-populate live examiner home directory at boot before login
    systemd.tmpfiles.rules = [
      "d /home/nixos 0755 nixos users -"
      "d /home/nixos/.config 0755 nixos users -"
      "d /home/nixos/.config/niri 0755 nixos users -"
      "d /home/nixos/.config/noctalia 0755 nixos users -"
      "d /home/nixos/Pictures 0755 nixos users -"
      "d /home/nixos/Pictures/Wallpapers 0755 nixos users -"
      "C /home/nixos/.config/niri/config.kdl 0644 nixos users - ${../../configs/niri/config.kdl}"
      "C /home/nixos/.config/niri/noctalia.kdl 0644 nixos users - ${../../configs/niri/noctalia.kdl}"
      "C /home/nixos/.config/noctalia/settings.json 0644 nixos users - ${../../configs/noctalia/settings.json}"
      "C /home/nixos/.config/noctalia/plugins.json 0644 nixos users - ${pkgs.writeText "plugins.json" "{\"version\":2,\"states\":{},\"sources\":[]}"}"
      "C /home/nixos/Pictures/DF_K-BG02.png 0644 nixos users - ${../../configs/assets/wallpaper.png}"
      "C /home/nixos/Pictures/Wallpapers/DF_K-BG02.png 0644 nixos users - ${../../configs/assets/wallpaper.png}"
    ];

    # 6. Fallback activation script for skel and persistent users
    system.activationScripts.dfnixNiriConfig = ''
      mkdir -p /etc/skel/.config/niri /etc/skel/.config/noctalia /etc/skel/Pictures/Wallpapers
      cp -f ${../../configs/niri/config.kdl} /etc/skel/.config/niri/config.kdl 2>/dev/null || true
      cp -f ${../../configs/niri/noctalia.kdl} /etc/skel/.config/niri/noctalia.kdl 2>/dev/null || true
      cp -f ${../../configs/noctalia/settings.json} /etc/skel/.config/noctalia/settings.json 2>/dev/null || true
      cp -f ${../../configs/assets/wallpaper.png} /etc/skel/Pictures/DF_K-BG02.png 2>/dev/null || true
      cp -f ${../../configs/assets/wallpaper.png} /etc/skel/Pictures/Wallpapers/DF_K-BG02.png 2>/dev/null || true
    '';
  };
}
