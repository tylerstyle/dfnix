# Bootable live forensic ISO (copy-to-RAM, UEFI + BIOS)
{ lib, modulesPath, ... }:

{
  imports = [
    # Base installation CD/DVD configuration (without calamares disk polling)
    (modulesPath + "/installer/cd-dvd/installation-cd-base.nix")
    ./base.nix
    ./field.nix
    ../modules/iso/live-iso.nix
  ];

  # Rapid prototyping VM resources (applied when building system.build.vm)
  virtualisation.vmVariant = { pkgs, ... }: {
    virtualisation.memorySize = 8192; # 8 GiB RAM
    virtualisation.cores = 4;         # 4 CPU cores
    virtualisation.efi.OVMF = pkgs.OVMF // { systemManagementModeRequired = false; };
    boot.kernelParams = lib.mkVMOverride [ "panic=10" "noresume" "nohibernate" ]; # Skip copytoram in VM closure
    boot.initrd.systemd.services.copytoram.enable = false;
  };
}
