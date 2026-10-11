# VirtualBox appliance (.ova)
{ lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/virtualbox-image.nix")
    ./appliance.nix
  ];

  networking.hostName = "df-vbox";

  # OS disk slot: SATA port 0 of the OVA's AHCI controller (PCI 00:0d.0)
  dfnix.writeBlocking.exemptIdPaths = [ "pci-0000:00:0d.0-ata-1.0" "pci-0000:00:0d.0-ata-1" ];

  # Forensic safety: Inhibit swap file on disk
  swapDevices = lib.mkForce [ ];

  # Resource sizing for forensic workloads
  virtualbox.memorySize = 8192; # 8 GiB RAM
  virtualbox.params.cpus = 4;   # 4 vCPUs
  virtualisation.diskSize = 30720; # 30 GiB

  # Forensic guest isolation defaults
  virtualisation.virtualbox.guest = {
    clipboard = false;
    dragAndDrop = false;
    seamless = false;
    vboxsf = false;
  };
}
