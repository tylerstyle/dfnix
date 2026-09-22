{ config, lib, pkgs, ... }:

with lib;

{
  options.dfnix.writeBlocking = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enforce strict forensic software write-blocking on all attached block devices.";
    };
  };

  config = mkIf config.dfnix.writeBlocking.enable {
    # --------------------------------------------------------------------------
    # Layer 1: Kernel Commandline & Systemd Boot Flags
    # --------------------------------------------------------------------------
    boot.kernelParams = [
      # Disable systemd Discoverable Partitions Specification (DPS)
      # Prevents auto-mounting of /home, /srv, and crucially SWAP partitions on GPT disks
      "systemd.gpt_auto=0"
      "systemd.swap=0"
    ];

    # Completely mask swap target to guarantee evidence disks with swap partitions
    # are never used as virtual memory (which destroys volatile evidence)
    systemd.targets.swap.enable = false;

    # --------------------------------------------------------------------------
    # Layer 2: Udev Rules for Immediate Read-Only Enforcement
    # --------------------------------------------------------------------------
    services.udev.extraRules = ''
      # 1. Neutralize Swap Partitions on attached evidence drives
      ENV{ID_FS_TYPE}=="swap", ENV{SYSTEMD_READY}="0"

      # 2. Force Read-Only at the kernel block level for all disk and partition nodes
      ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd*|nvme*|mmcblk*|vd*|xvd*|loop*|dm-*|md*|nbd*", \
        ATTR{ro}="1", \
        RUN+="${pkgs.util-linux}/bin/blockdev --setro $env{DEVNAME}"

      # 3. Prevent udisks2 and desktop volume managers from automounting or probing
      ACTION=="add|change", SUBSYSTEM=="block", \
        ENV{UDISKS_IGNORE}="1", \
        ENV{UDISKS_AUTO}="0", \
        ENV{UDISKS_SYSTEM}="1"

      # 4. Inhibit automatic MDADM RAID array assembly on hotplug
      SUBSYSTEM=="block", ACTION=="add", ENV{ID_FS_TYPE}=="linux_raid_member", ENV{SYSTEMD_READY}="0"
    '';

    # --------------------------------------------------------------------------
    # Layer 3: Storage Daemon Lockdown (LVM, RAID, Polkit)
    # --------------------------------------------------------------------------
    services.lvm.boot.thin.enable = false;
    environment.etc."lvm/lvm.conf".text = ''
      activation {
        event_activation = 0
        auto_activation_volume_list = []
      }
    '';

    environment.etc."mdadm/mdadm.conf".text = ''
      AUTO -all
    '';

    # Polkit rules to prevent unauthorized or automatic userspace mounts
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id.indexOf("org.freedesktop.udisks2.filesystem-mount") == 0 ||
            action.id.indexOf("org.freedesktop.udisks2.encrypted-unlock") == 0) {
          if (!subject.isInGroup("wheel")) {
            return polkit.Result.NO;
          }
        }
      });
    '';

    # Core system tools for block device control and inspection
    environment.systemPackages = with pkgs; [
      util-linux
      lvm2
      e2fsprogs
      xfsprogs
      btrfs-progs
      dosfstools
      exfatprogs
      ntfs3g
    ];
  };
}
