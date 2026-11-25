# The second live image: the standard one (profiles/live.nix) with NVIDIA's
# driver and a CUDA runtime, for machines with an NVIDIA Turing or newer card.
# It contains unfree software; see modules/iso/nvidia-open.nix.
#
# Named apart everywhere it shows: the file (dfnix-forensics-nvidia.iso), the
# boot menu, and DFNIX_VARIANT in /etc/dfnix-release. The volume label is the
# same DFNIX_LIVE: system-device protection knows the live medium by it.
{ lib, ... }:

{
  imports = [
    ./live.nix
    ../modules/iso/nvidia-open.nix
  ];

  # Above the standard image's own settings, below a boot entry's (a
  # specialisation names itself with mkForce)
  image.baseName = lib.mkOverride 40 "dfnix-forensics-nvidia";
  isoImage.appendToMenuLabel = lib.mkOverride 90 " Forensic Acquisition OS, NVIDIA driver and CUDA (Copy-to-RAM)";
}
