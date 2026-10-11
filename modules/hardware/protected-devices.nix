# Boot-time registry of devices that must never be written (dfcore): the disks
# holding the running system and the live medium, identified by serial/WWN. Written
# to /run/dfnix/protected.json before the desktop starts; dfdisk and dfmount refuse
# anything it lists, even after it is unmounted or re-enumerates under another name.
# The same step opens the boot's audit chain (/run/dfnix/audit.jsonl).
{ config, lib, pkgs, ... }:

let
  cfg = config.dfnix.protectedDevices;
in
{
  options.dfnix.protectedDevices.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Write the dfcore protected-device registry at boot.";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.dfcore ];

    systemd.tmpfiles.rules = [ "d /run/dfnix 0755 root root -" ];

    systemd.services.dfnix-protected-devices = {
      description = "Record dfnix protected devices (system disks, live medium)";
      wantedBy = [ "multi-user.target" ];
      wants = [ "systemd-udev-settle.service" ];
      after = [ "systemd-udev-settle.service" "local-fs.target" "systemd-tmpfiles-setup.service" ];
      before = [ "display-manager.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.dfcore}/bin/dfcore-protect";
      };
    };
  };
}
