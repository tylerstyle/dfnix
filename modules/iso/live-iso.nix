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
    "rtsx_pci_sdmmc"
    "rtsx_usb_sdmmc"
  ];

  boot.kernelParams = [
    # USB initialization stability for legacy USB 2.0 drives on modern xHCI
    "usbcore.autosuspend=-1"
    "usbcore.initial_descriptor_timeout=2000"
    "panic=10"
  ];

  # Allocate large RAM tmpfs for carving and volatile triage
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "80%";

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
