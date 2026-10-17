# Desktop launchers for the dfnix forensic tools
{ pkgs, ... }: {
  environment.systemPackages = [
    (pkgs.makeDesktopItem {
      name = "dfdisk";
      desktopName = "dfdisk Forensic Imager";
      genericName = "Forensic Disk Imaging & Rescue TUI";
      comment = "Acquire E01/RAW images, rescue failing disks with ddrescue, and verify hashes";
      exec = "kitty --title \"dfdisk - Forensic Imager\" sudo dfdisk";
      icon = "drive-harddisk-system";
      categories = [ "System" "Utility" ];
      keywords = [ "forensics" "evidence" "ddrescue" "e01" "imaging" "disk" ];
    })
    (pkgs.makeDesktopItem {
      name = "dfmount";
      desktopName = "dfmount Forensic Storage TUI";
      genericName = "Forensic Disk Mounter TUI";
      comment = "Mount evidence write-blocked with zero journal replay or unblock target drives";
      exec = "kitty --title \"dfmount - Forensic Storage Manager\" sudo dfmount";
      icon = "drive-harddisk-system";
      categories = [ "System" "Utility" ];
      keywords = [ "forensics" "mount" "writeblock" "target" "dfdisk" ];
    })
    (pkgs.makeDesktopItem {
      name = "dfnet";
      desktopName = "dfnet Network Triage";
      genericName = "Forensic Network Operations";
      comment = "MAC spoofing, static IP setup (nmtui), network share mounting, and raw disk reception";
      exec = "kitty --title \"dfnet - Forensic Network Operations\" sudo dfnet";
      icon = "network-workgroup";
      categories = [ "System" "Network" ];
      keywords = [ "forensics" "network" "macchanger" "nmtui" "smb" "nfs" ];
    })
    (pkgs.makeDesktopItem {
      name = "dfcollect";
      desktopName = "dfcollect Logical Acquisition";
      genericName = "Forensic Logical Acquisition TUI";
      comment = "Acquire the files in scope from a read-only mount into a verifiable container, preview the scope first, and verify collections";
      exec = "kitty --title \"dfcollect - Logical Acquisition\" sudo dfcollect";
      icon = "document-save";
      categories = [ "System" "Utility" ];
      keywords = [ "forensics" "evidence" "logical" "files" "scope" "collection" "verify" ];
    })
    (pkgs.makeDesktopItem {
      name = "dfinfo";
      desktopName = "dfinfo Forensic Triage";
      genericName = "Forensic System Triage & Fastfetch";
      comment = "System hardware triage, fastfetch overview, and concise forensic documentation";
      exec = "kitty --title \"dfinfo - Forensic System Triage\" sudo dfinfo";
      icon = "utilities-system-monitor";
      categories = [ "System" "Utility" ];
      keywords = [ "forensics" "triage" "fastfetch" "system" "hardware" "evidence" ];
    })
    (pkgs.makeDesktopItem {
      name = "dfnix-guide";
      desktopName = "dfnix Quick Start Guide";
      genericName = "Forensic Quick Start & Navigation Guide";
      comment = "Guide for storage mounting, hardware triage, disk imaging, and Niri navigation";
      exec = "dfnix-guide";
      icon = "help-browser";
      categories = [ "System" "Documentation" "Utility" ];
      keywords = [ "guide" "help" "documentation" "quickstart" "niri" "dfdisk" "dfmount" "dfinfo" "forensics" ];
    })
  ];
}
