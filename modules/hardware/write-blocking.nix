{ config, lib, pkgs, ... }:

with lib;

let
  writeBlockUdevPackage = pkgs.writeTextFile {
    name = "10-dfnix-write-blocking.rules";
    destination = "/etc/udev/rules.d/10-dfnix-write-blocking.rules";
    text = ''
      # ==============================================================================
      # dfnix Early-Stage Hardware Forensic Write-Blocking & Storage Ingestion Shield
      # Priority: 10 (Evaluated before 64-md-raid-assembly, 69-lvm, and standard udev)
      # ==============================================================================

      # 1. Neutralize Swap Partitions on attached evidence drives
      ENV{ID_FS_TYPE}=="swap", ENV{SYSTEMD_READY}="0"

      # 2. Inhibit automatic MDADM RAID array assembly on hotplug or coldplug
      SUBSYSTEM=="block", ACTION=="add", ENV{ID_FS_TYPE}=="linux_raid_member", ENV{SYSTEMD_READY}="0"

      # 3. Force Read-Only at the kernel block level for physical attached storage
      # Restrict to physical and hypervisor block devices (SATA/SCSI/USB, NVMe, MMC/SD, VirtIO, Xen).
      # Exclude synthetic/mapped devices (loop*, dm-*, md*, nbd*) to allow decrypted LUKS
      # target containers, software RAID arrays, and live system overlays to function writeable.
      # Note: We omit filesystem-label-based exemptions (e.g. DFNIX_LIVE) so evidence disks
      # cannot evade write-blocking by adopting a spoofed filesystem label.
      ACTION=="add", SUBSYSTEM=="block", \
        KERNEL=="sd[a-z]*|nvme[0-9]*n[0-9]*|nvme[0-9]*n[0-9]*p[0-9]*|mmcblk[0-9]*|mmcblk[0-9]*p[0-9]*|vd[a-z]*|xvd[a-z]*", \
        ATTR{ro}="1", \
        RUN+="${pkgs.util-linux}/bin/blockdev --setro $env{DEVNAME}"

      # 4. Handle genuine media insertion in removable card readers
      ACTION=="change", SUBSYSTEM=="block", ENV{DISK_MEDIA_CHANGE}=="1", \
        KERNEL=="sd[a-z]*|mmcblk[0-9]*|mmcblk[0-9]*p[0-9]*", \
        ATTR{ro}="1", \
        RUN+="${pkgs.util-linux}/bin/blockdev --setro $env{DEVNAME}"

      # 5. Prevent udisks2 and desktop volume managers from automounting or probing
      ACTION=="add|change", SUBSYSTEM=="block", \
        ENV{UDISKS_IGNORE}="1", \
        ENV{UDISKS_AUTO}="0", \
        ENV{UDISKS_SYSTEM}="1"
    '';
  };
in
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
    # Layer 2: Udev Rules for Immediate Read-Only Enforcement (Initrd & Stage-2)
    # --------------------------------------------------------------------------
    # Install priority-10 write-blocking udev rules in both stage 1 (initrd) and stage 2
    services.udev.packages = [ writeBlockUdevPackage ];
    boot.initrd.services.udev.packages = [ writeBlockUdevPackage ];
    boot.initrd.services.udev.binPackages = [ pkgs.util-linux ];
    boot.initrd.systemd.extraBin.blockdev = "${pkgs.util-linux}/bin/blockdev";

    # --------------------------------------------------------------------------
    # Layer 3: Storage Daemon Lockdown (LVM, RAID, Polkit)
    # --------------------------------------------------------------------------
    # Prohibit automatic MD RAID assembly across both stage 1 (initrd) and stage 2
    boot.swraid.enable = mkForce false;
    boot.swraid.mdadmConf = mkForce "AUTO -all\n";
    environment.etc."mdadm.conf".text = mkForce "AUTO -all\n";
    environment.etc."mdadm/mdadm.conf".text = mkForce "AUTO -all\n";
    boot.initrd.systemd.contents."/etc/mdadm.conf".text = mkForce "AUTO -all\n";

    # Restrict LVM automatic event activation across both stage 1 (initrd) and stage 2
    services.lvm.boot.thin.enable = false;
    environment.etc."lvm/lvm.conf".text = ''
      activation {
        event_activation = 0
        auto_activation_volume_list = []
      }
    '';
    boot.initrd.systemd.contents."/etc/lvm/lvm.conf".text = ''
      activation {
        event_activation = 0
        auto_activation_volume_list = []
      }
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
