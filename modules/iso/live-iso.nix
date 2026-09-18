{ config, lib, pkgs, ... }:

{
  # ----------------------------------------------------------------------------
  # Live ISO Image Settings
  # ----------------------------------------------------------------------------
  image.baseName = lib.mkForce "dfnix-forensics";
  isoImage = {
    volumeID = "DFNIX_LIVE";

    # Hybrid bootloader: boots on both modern UEFI and legacy BIOS
    makeBiosBootable = true;
    makeEfiBootable = true;
    makeUsbBootable = true;

    # Ultra-fast zstd decompression (>1.5GB/s) to accelerate copytoram boot
    squashfsCompression = "zstd -Xcompression-level 19";
  };

  # ----------------------------------------------------------------------------
  # Bootloader & Kernel Configuration
  # ----------------------------------------------------------------------------
  boot.loader.grub.memtest86.enable = true;

  boot.kernelParams = [
    # Boot entirely into RAM so examiner can eject live USB
    # Eliminates USB bus contention when imaging suspect drives
    "copytoram"
    "quiet"
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
