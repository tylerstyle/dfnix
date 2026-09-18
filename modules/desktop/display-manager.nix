{ config, lib, pkgs, ... }:

with lib;

{
  options.dfnix.desktop.displayManager = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable SDDM Display Manager with Niri as primary and XFCE as fallback.";
    };
  };

  config = mkIf config.dfnix.desktop.displayManager.enable {
    services.displayManager = {
      defaultSession = lib.mkDefault "niri";
      sddm = {
        enable = true;
        wayland.enable = true;
        autoLogin = {
          enable = true;
          user = "nixos";
        };
      };
    };

    # Live ISO user privileges
    users.users.nixos = {
      isNormalUser = true;
      extraGroups = [ "wheel" "disk" "storage" "networkmanager" "video" "audio" ];
      description = "Forensic Field Examiner";
    };

    # Passwordless sudo for forensic acquisition tools in the field
    security.sudo.wheelNeedsPassword = false;
  };
}
