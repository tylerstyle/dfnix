{ config, lib, pkgs, ... }:

{
  # ----------------------------------------------------------------------------
  # Live ISO Image Settings
  # ----------------------------------------------------------------------------
  image.baseName = lib.mkForce "dfnix-forensics";
  system.nixos.distroName = "dfnix";
  isoImage = {
    volumeID = "DFNIX_LIVE";
    appendToMenuLabel = " Forensic Field OS (Niri/XFCE)";

    # Hybrid bootloader: boots on both modern UEFI and legacy BIOS
    makeBiosBootable = true;
    makeEfiBootable = true;
    makeUsbBootable = true;

    # Ultra-fast zstd decompression (>1.5GB/s) to accelerate boot
    squashfsCompression = "zstd";
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
    "rtsx_pci_sdmmc"
    "rtsx_usb_sdmmc"
  ];

  boot.kernelParams = [
    # Boot entirely into RAM (eliminates CD-ROM loopback LBA readahead errors on Zalman / virtual ODDs)
    "copytoram"
    # USB initialization stability for legacy USB 2.0 drives on modern xHCI
    "usbcore.autosuspend=-1"
    "usbcore.initial_descriptor_timeout=2000"
    "panic=10"
  ];

  # Allocate large RAM tmpfs for carving and volatile triage
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "80%";

  # Fix upstream NixOS copytoram bug: provide generous headroom so tmpfs never
  # runs out of space due to metadata and 4KB page rounding ("No space left on device")
  boot.initrd.systemd.services.copytoram.script = lib.mkForce ''
    device=$(findmnt -n -o SOURCE --target /sysroot/iso)
    fsSize=$(blockdev --getsize64 "$device" 2>/dev/null || stat -Lc '%s' "$device" 2>/dev/null || echo "4294967296")
    extraBytes=$(( 2048 * 1024 * 1024 ))
    targetSize=$(( fsSize + extraBytes ))
    echo ">>> dfnix: Allocating $targetSize bytes RAM tmpfs for live forensic store..."
    mkdir -p /tmp-iso
    mount --bind --make-private /sysroot/iso /tmp-iso
    umount /sysroot/iso
    mount -t tmpfs -o size="$targetSize" tmpfs /sysroot/iso
    echo ">>> dfnix: Copying forensic live OS into RAM..."
    cp -r /tmp-iso/* /sysroot/iso/
    umount /tmp-iso
    rm -r /tmp-iso
    echo ">>> dfnix: Live OS successfully loaded into RAM."
  '';

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
