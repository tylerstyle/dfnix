{ config, lib, pkgs, ... }:

{
  # ----------------------------------------------------------------------------
  # Live ISO Image Settings
  # ----------------------------------------------------------------------------
  image.baseName = lib.mkForce "dfnix-forensics";
  system.nixos.distroName = "dfnix";
  system.nixos.label = "live";
  isoImage = {
    volumeID = "DFNIX_LIVE";
    appendToMenuLabel = " Forensic Acquisition OS (Copy-to-RAM)";

    # Hybrid bootloader: boots on both modern UEFI and legacy BIOS
    makeBiosBootable = true;
    makeEfiBootable = true;
    makeUsbBootable = true;

    # Ultra-fast zstd decompression (>1.5GB/s) to accelerate boot
    squashfsCompression = "zstd -Xcompression-level 19";
  };

  # ----------------------------------------------------------------------------
  # Bootloader & Kernel Configuration
  # ----------------------------------------------------------------------------
  boot.loader.grub.memtest86.enable = true;

  # Ensure all common storage & USB controllers are available in stage-1 initrd
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ehci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "uas"
    "sd_mod"
    "sr_mod"
    "cdrom"
    "isofs"
    "sg"
    "rtsx_pci_sdmmc"
    "rtsx_usb_sdmmc"
  ];

  boot.kernelParams = [
    # Boot entirely into RAM (eliminates CD-ROM loopback LBA readahead errors on Zalman / virtual ODDs)
    "copytoram"
    # USB initialization stability for external drives & virtual ODDs (Zalman/IODD) on modern xHCI
    "usbcore.autosuspend=-1"
    "usbcore.initial_descriptor_timeout=15000"
    "rootdelay=5"
    "panic=10"
  ];

  # Allocate large RAM tmpfs for carving and volatile triage
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "80%";

  # Fix upstream NixOS copytoram bug: upstream uses `blockdev --getsize64 "$device" || stat -Lc '%s' "$device"`.
  # On optical drives / virtual ODDs (e.g. Zalman /dev/sr0), blockdev ioctl can fail and stat on a device node
  # returns 0 bytes with exit 0, causing a 0-byte or undersized tmpfs and fatal "No space left on device".
  # Here we inspect total RAM and actual ISO size, enforce a safety floor, and allocate 80% RAM for tmpfs
  # (which only consumes physical RAM for written blocks, ~3.5GB).
  boot.initrd.systemd.services.copytoram = {
    path = [
      pkgs.coreutils
      config.boot.initrd.systemd.package.util-linux
    ];
    script = lib.mkForce ''
      echo ">>> dfnix: Evaluating system memory for live forensic store..."

      # Skip if /sysroot/iso is not mounted (e.g. in a QEMU VM or persistent installation)
      if [ ! -d /sysroot/iso ] || ! mountpoint -q /sysroot/iso 2>/dev/null; then
        echo ">>> dfnix: /sysroot/iso is not mounted, skipping copy-to-RAM."
        exit 0
      fi

      # Detect total RAM from /proc/meminfo
      read -r _ mem_total_kb _ < /proc/meminfo || true
      mem_total_mb=$(( ''${mem_total_kb:-0} / 1024 ))
      echo ">>> dfnix: Total System RAM: ''${mem_total_mb} MB"

      # Measure live ISO size on /sysroot/iso (following mount symlinks if any)
      iso_size_kb=$(du -skL /sysroot/iso 2>/dev/null | cut -f1 || echo "4194304")
      if [ -z "$iso_size_kb" ] || [ "$iso_size_kb" -lt 1000000 ]; then
        iso_size_kb=4194304
      fi
      iso_size_mb=$(( iso_size_kb / 1024 ))
      echo ">>> dfnix: Live Forensic Image Size: ''${iso_size_mb} MB"

      # Require ISO size + 2048 MB RAM headroom to prevent OOM
      min_required_mb=$(( iso_size_mb + 2048 ))
      if [ "$mem_total_mb" -lt "$min_required_mb" ]; then
        echo ">>> dfnix: WARNING: Total RAM (''${mem_total_mb} MB) is below safe copytoram threshold (''${min_required_mb} MB)."
        echo ">>> dfnix: Skipping copy-to-RAM; booting directly from storage media."
        exit 0
      fi

      # Set tmpfs size quota to 80% of RAM (or ISO size + 1024MB, whichever is larger)
      target_mb=$(( mem_total_mb * 80 / 100 ))
      if [ "$target_mb" -lt "$(( iso_size_mb + 1024 ))" ]; then
        target_mb=$(( iso_size_mb + 1024 ))
      fi
      echo ">>> dfnix: Allocating ''${target_mb} MB RAM tmpfs for live forensic store..."

      mkdir -p /tmp-iso
      if ! mount --bind --make-private /sysroot/iso /tmp-iso; then
        echo ">>> dfnix: WARNING: Failed to bind-mount /sysroot/iso. Booting directly from storage media."
        exit 0
      fi

      if ! umount /sysroot/iso && ! umount -l /sysroot/iso; then
        echo ">>> dfnix: WARNING: Failed to unmount /sysroot/iso. Booting directly from storage media."
        umount /tmp-iso 2>/dev/null || true
        rm -rf /tmp-iso 2>/dev/null || true
        exit 0
      fi

      if ! mount -t tmpfs -o "size=''${target_mb}M" tmpfs /sysroot/iso; then
        echo ">>> dfnix: WARNING: Failed to mount tmpfs on /sysroot/iso. Restoring original mount."
        mount --bind /tmp-iso /sysroot/iso 2>/dev/null || true
        umount /tmp-iso 2>/dev/null || true
        rm -rf /tmp-iso 2>/dev/null || true
        exit 0
      fi

      echo ">>> dfnix: Copying forensic live OS into RAM (please wait)..."
      if cp -r /tmp-iso/* /sysroot/iso/ 2>/dev/null || cp -a /tmp-iso/. /sysroot/iso/ 2>/dev/null; then
        echo ">>> dfnix: Live OS successfully loaded into RAM. Boot media may now be safely removed."
        umount /tmp-iso 2>/dev/null || umount -l /tmp-iso 2>/dev/null || true
        rm -rf /tmp-iso 2>/dev/null || true
      else
        echo ">>> dfnix: ERROR: Copy to RAM failed! Falling back to booting directly from storage media."
        umount /sysroot/iso 2>/dev/null || umount -l /sysroot/iso 2>/dev/null || true
        mount --bind /tmp-iso /sysroot/iso 2>/dev/null || true
        umount /tmp-iso 2>/dev/null || true
        rm -rf /tmp-iso 2>/dev/null || true
      fi
    '';
  };

  # ----------------------------------------------------------------------------
  # 100% Offline Air-Gapped Usability
  # ----------------------------------------------------------------------------
  # Pre-index manpages and documentation so 'man' and 'apropos' work offline
  documentation.enable = true;
  documentation.man.enable = true;
  documentation.man.cache.enable = true;
  documentation.doc.enable = true;

  # Air-gap network settings (no lingering wait-online timeouts)
  networking.hostName = "df-forensics";
  networking.networkmanager.enable = true;
  systemd.services.NetworkManager-wait-online.enable = false;

  # Timezone & Localization
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "de";
}
