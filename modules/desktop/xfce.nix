{ config, lib, pkgs, ... }:

with lib;

{
  options.dfnix.desktop.xfce = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable XFCE4 as lightweight, fail-safe desktop fallback for legacy BIOS/GPUs.";
    };
  };

  config = mkIf config.dfnix.desktop.xfce.enable {
    services.xserver = {
      enable = true;
      desktopManager.xfce = {
        enable = true;
        enableScreensaver = false;
      };
    };

    # CRITICAL FORENSIC SAFEGUARD:
    # Disable automatic volume mounting in XFCE / Thunar
    programs.thunar.plugins = mkForce [];

    # Ensure wallpaper script is triggered if XFCE session is active
    systemd.user.services.xfce-forensic-wallpaper = {
      description = "Set DF Forensic Wallpaper on XFCE fallback session";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      script = ''
        if [ "$XDG_CURRENT_DESKTOP" = "XFCE" ] && command -v xfconf-query >/dev/null 2>&1; then
          xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s "${../../configs/assets/wallpapers/digitale-forensik.jpg}" || true
        fi
      '';
    };
  };
}
