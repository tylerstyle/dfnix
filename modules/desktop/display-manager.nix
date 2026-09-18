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
      autoLogin = {
        enable = true;
        user = "nixos";
      };
      sddm = {
        enable = true;
        wayland.enable = true;
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
