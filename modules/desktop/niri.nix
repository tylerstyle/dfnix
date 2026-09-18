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
      NIXOS_OZONE_WL = "1";
      QT_QPA_PLATFORM = "wayland;xcb";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      MOZ_ENABLE_WAYLAND = "1";
      XDG_CURRENT_DESKTOP = "Niri";
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

    # 4. System-wide XDG configuration fallbacks (ensures Niri & Noctalia never launch unconfigured)
    environment.etc = {
      "xdg/niri/config.kdl".source = ../../configs/niri/config.kdl;
      "xdg/niri/noctalia.kdl".source = ../../configs/niri/noctalia.kdl;
      "xdg/noctalia/settings.json".source = ../../configs/noctalia/settings.json;
      "xdg/noctalia/plugins.json".text = ''{"version":2,"states":{},"sources":[]}'';
      "xdg/dfnix/wallpaper.png".source = ../../configs/assets/wallpaper.png;
    };

    # 4. Deploy default Niri and Noctalia dotfiles for live examiner user
    system.activationScripts.dfnixNiriConfig = ''
      mkdir -p /etc/skel/.config/niri /etc/skel/.config/noctalia /etc/skel/Pictures/Wallpapers
      cp -f ${../../configs/niri/config.kdl} /etc/skel/.config/niri/config.kdl 2>/dev/null || true
      cp -f ${../../configs/niri/noctalia.kdl} /etc/skel/.config/niri/noctalia.kdl 2>/dev/null || true
      cp -f ${../../configs/noctalia/settings.json} /etc/skel/.config/noctalia/settings.json 2>/dev/null || true
      cp -f ${../../configs/assets/wallpaper.png} /etc/skel/Pictures/DF_K-BG02.png 2>/dev/null || true
      cp -f ${../../configs/assets/wallpaper.png} /etc/skel/Pictures/Wallpapers/DF_K-BG02.png 2>/dev/null || true

      # If live user 'nixos' already exists in RAM during boot:
      if id nixos &>/dev/null; then
        HOME_NIXOS="/home/nixos"
        mkdir -p "$HOME_NIXOS/.config/niri" "$HOME_NIXOS/.config/noctalia" "$HOME_NIXOS/Pictures/Wallpapers"
        cp -f ${../../configs/niri/config.kdl} "$HOME_NIXOS/.config/niri/config.kdl"
        cp -f ${../../configs/niri/noctalia.kdl} "$HOME_NIXOS/.config/niri/noctalia.kdl"
        cp -f ${../../configs/noctalia/settings.json} "$HOME_NIXOS/.config/noctalia/settings.json"
        cp -f ${../../configs/assets/wallpaper.png} "$HOME_NIXOS/Pictures/DF_K-BG02.png"
        cp -f ${../../configs/assets/wallpaper.png} "$HOME_NIXOS/Pictures/Wallpapers/DF_K-BG02.png"
        chown -R nixos:users "$HOME_NIXOS" || true
      fi
    '';
  };
}
