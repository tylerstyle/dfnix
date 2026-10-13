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

    # Noctalia is the notification daemon on niri. xfce4-notifyd's D-Bus service
    # file would let any early notification activate it there and take
    # org.freedesktop.Notifications first ("DBus notifications disabled ...
    # owned by another service"). Drop the package (D-Bus activation, user unit)
    # and start the daemon from an autostart entry only XFCE sessions run.
    environment.xfce.excludePackages = [ pkgs.xfce4-notifyd ];
    environment.etc."xdg/autostart/xfce4-notifyd.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Xfce Notification Daemon
      Exec=${pkgs.xfce4-notifyd}/lib/xfce4/notifyd/xfce4-notifyd
      OnlyShowIn=XFCE;
    '';

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
