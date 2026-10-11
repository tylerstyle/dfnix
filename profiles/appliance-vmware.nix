# VMware Workstation / Fusion / ESXi appliance (.vmdk)
{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/vmware-image.nix")
    ./appliance.nix
  ];

  networking.hostName = "df-vmware";

  # OS disk slot in configs/vmware/dfnix-forensics.vmx (scsi0:0, LSI Logic at PCI 00:10.0)
  dfnix.writeBlocking.exemptIdPaths = [ "pci-0000:00:10.0-scsi-0:0:0:0" ];

  # Sizable VMDK capacity for forensic analysis & triage staging
  virtualisation.diskSize = 30720; # 30 GiB (sparse VMDK)
}
