# VMware / VirtualBox appliance shared settings. The hypervisor profiles add the
# image format and the controller slot of the appliance's own OS disk.
{
  imports = [
    ./base.nix
    ./field.nix
  ];

  # VM appliances present graphical chooser at boot to select Niri or XFCE
  dfnix.desktop.displayManager.enable = true;
  dfnix.desktop.displayManager.defaultDesktop = "chooser";

  # Write-block every attached disk except the appliance OS disk (dfnix.writeBlocking.exemptIdPaths)
  dfnix.writeBlocking.enable = true;
  dfnix.writeBlocking.readOnlyAll = true;

  system.stateVersion = "24.11";
}
