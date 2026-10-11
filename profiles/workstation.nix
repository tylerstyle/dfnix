# Persistent lab workstation: forensic storage invariants (swap masking, RAID/LVM
# lockdown, GPT auto-discovery off, registry) while the OS disk stays writable,
# and a normal login.
{ lib, ... }:

{
  imports = [ ./base.nix ];

  dfnix.writeBlocking.enable = lib.mkDefault true;
  dfnix.writeBlocking.readOnlyAll = lib.mkDefault false;
  dfnix.desktop.displayManager.autologin = lib.mkDefault false;
}
