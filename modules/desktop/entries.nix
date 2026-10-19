# Desktop launchers for the dfnix forensic tools
{ pkgs, ... }:
let
  dfkit-shell = pkgs.writeShellApplication {
    name = "dfkit-shell";
    runtimeInputs = [
      pkgs.dfkit
      pkgs.util-linux
    ];
    text = ''
      cat <<'EOF'
      === dfkit: Forensic Field-Kit Sticks ===

      Target USB stick must be write-unblocked first:
        sudo dfmount unblock /dev/sdX

      Write field-kit stick:
        sudo dfkit write /etc/dfnix/fieldkit /dev/sdX --confirm sdX

      Verify field-kit stick:
        sudo dfkit verify /dev/sdX

      Block devices:
      EOF
      lsblk -o NAME,SIZE,TRAN,MODEL,RM,RO || true
      echo
      exec bash
    '';
  };
in
{
  environment.systemPackages = [
    pkgs.dfnix-guide
    dfkit-shell
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
      name = "dfkit";
      desktopName = "dfkit Field-Kit Sticks";
      genericName = "Forensic Field-Kit Sticks";
      comment = "Write and verify multi-partition forensic field-kit USB sticks";
      exec = "kitty --title \"dfkit - Field-Kit Sticks\" dfkit-shell";
      icon = "drive-removable-media";
      categories = [ "System" "Utility" ];
      keywords = [ "forensics" "fieldkit" "usb" "stick" "write" "verify" ];
    })
  ];
}
