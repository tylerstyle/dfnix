{ config, lib, pkgs, ... }:

with lib;

let
  # acquire and dissect-target don't support nixpkgs' default Python (3.14) yet
  acquire = pkgs.python313Packages.toPythonApplication pkgs.python313Packages.acquire;

  # dissect's command-line tools (target-query, target-shell, target-fs, rdump,
  # vma-extract, ...) with every dissect module, so they read VMFS, VMDK, VHDX
  # and the other formats. The environment's interpreter stays off the PATH.
  dissectEnv = pkgs.python313.withPackages (
    ps: [ ps.dissect ] ++ ps.dissect-target.optional-dependencies.full
  );
  dissect = pkgs.runCommand "dissect-tools-${pkgs.python313Packages.dissect.version}" { } ''
    mkdir -p $out/bin
    for tool in ${dissectEnv}/bin/*; do
      case "''${tool##*/}" in
        python* | idle* | pydoc* | ipython* | pygmentize | cffi-gen-src | cstruct-stubgen) ;;
        *) ln -s "$tool" $out/bin/ ;;
      esac
    done
  '';
in
{
  options.dfnix.forensics = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Install the complete digital forensics and incident response (DFIR) toolkit.";
    };
  };

  config = mkIf config.dfnix.forensics.enable {
    # Procedures the tools point to (e.g. dfmount for RAID, LVM and ZFS members)
    environment.etc."dfnix/playbooks".source = ../../docs/playbooks;

    # Supported filesystems for forensic mounting
    boot.supportedFilesystems = [
      "btrfs"
      "ext4"
      "f2fs"
      "ntfs"
      "vfat"
      "xfs"
      # Read-only pool import only; the lockdown is in modules/hardware/write-blocking.nix
      "zfs"
    ];

    # Core system packages
    environment.systemPackages = with pkgs; [
      # ------------------------------------------------------------------------
      # Primary Forensic Imaging & Mounting Tools
      # ------------------------------------------------------------------------
      dfdisk                  # Examiner's high-speed TUI forensic imager
      dfmount                 # Forensic write-blocked mounter & target unblocker suite
      libewf                  # Expert Witness Compression Format tools (ewfacquire, ewfexport)
      dcfldd                  # Forensically enhanced dd with live hashing
      ddrescue                # GNU data recovery for damaged and failing media
      ddrescueview            # Graphical viewer for ddrescue mapfiles
      afflib                  # Advanced Forensics Format utilities
      qemu-utils              # qemu-nbd for mounting virtual disk images (.vmdk, .qcow2, .vhd)

      # ------------------------------------------------------------------------
      # File System Analysis, TSK & Carving
      # ------------------------------------------------------------------------
      sleuthkit               # The Sleuth Kit (fls, icat, mmls, fsstat, blkls)
      testdisk                # Partition recovery
      testdisk-qt             # Graphical Qt header-based file carver (qphotorec)
      foremost                # File carving tool
      scalpel                 # Multi-threaded file carving
      bulk_extractor          # Stream-based feature extraction (emails, URLs, credit cards)
      ext4magic               # Ext3/4 journal carving
      extundelete             # Ext3/4 undelete tool

      # ------------------------------------------------------------------------
      # Volume Decryption & Specialized Filesystem Drivers
      # ------------------------------------------------------------------------
      cryptsetup              # LUKS volume management
      dislocker               # BitLocker decryption
      libbde                  # BitLocker drive encryption library
      veracrypt               # TrueCrypt / VeraCrypt volume mounter
      apfs-fuse               # Apple APFS read-only FUSE driver
      apfsprogs               # APFS filesystem utilities
      ntfs3g                  # NTFS user-space driver
      btrfs-progs             # Btrfs utilities
      xfsprogs                # XFS utilities
      dosfstools              # FAT utilities
      exfatprogs              # ExFAT utilities

      # ------------------------------------------------------------------------
      # Memory Forensics
      # ------------------------------------------------------------------------
      volatility3             # Modern memory analysis framework
      dwarf2json              # Volatility 3 ISF table generator
      avml                    # Linux memory acquisition (live systems, static)

      # ------------------------------------------------------------------------
      # RAID, NAS & Self-Encrypting Drives
      # ------------------------------------------------------------------------
      mdadm                   # Manual read-only md assembly (md, DDF, IMSM, Synology SHR)
      thin-provisioning-tools # LVM thin pools (QNAP)
      sedutil                 # TCG Opal locking state of self-encrypting drives

      # ------------------------------------------------------------------------
      # Logical, Mail, Database & Hypervisor Acquisition
      # ------------------------------------------------------------------------
      acquire                 # Fox-IT forensic artifact collection from targets and images
      dissect                 # Fox-IT dissect tools: VMFS, VMDK, VHDX, volumes and targets
      libpff                  # PST/OST integrity check and export (pffinfo, pffexport)
      govc                    # VMware ESXi / vSphere snapshots and datastore downloads
      postgresql              # pg_dump, pg_dumpall, pg_basebackup, psql
      mariadb.client          # mariadb-dump and client for MySQL / MariaDB
      sqlcmd                  # Microsoft SQL Server client (COPY_ONLY backups)
      mongodb-tools           # mongodump
      age                     # Encrypt captured key material to the examiner
      minisign                # Sign reports and manifests

      # ------------------------------------------------------------------------
      # Artifacts, Windows Registry & Event Logs
      # ------------------------------------------------------------------------
      regripper               # Windows Registry hive artifact extractor
      chainsaw                # High-speed Windows event log (EVTX) hunter
      python3Packages.evtx    # Pure Python EVTX parser
      sqlitebrowser           # Visual SQLite database inspector

      # ------------------------------------------------------------------------
      # Network Forensics, Recon & Remote Acquisition
      # ------------------------------------------------------------------------
      dfnet                   # Forensic network operations & MAC spoofer
      macchanger              # MAC address spoofing / faking
      networkmanager          # Includes nmtui (interactive network TUI)
      arp-scan                # Local ARP network device discovery
      fping                   # Rapid parallel network pinging
      ethtool                 # Ethernet speed / duplex / link diagnostics
      iperf3                  # Network bandwidth throughput testing
      cifs-utils              # SMB/CIFS filesystem tools (mount.cifs)
      samba                   # smbclient for Windows share browsing
      nfs-utils               # NFS client (mount.nfs)
      sshfs                   # FUSE mount remote directories over SSH
      rsync                   # Remote incremental file copying
      rclone                  # Multi-protocol remote storage sync (SFTP, S3, WebDAV)
      openiscsi               # iSCSI client for connecting remote SAN/NAS targets
      netcat                  # Raw network stream piping
      socat                   # Advanced bidirectional data relay
      pv                      # Pipe viewer (live MB/s rate and progress monitor)
      wireshark               # Packet inspection GUI
      tshark                  # Terminal Wireshark
      tcpdump                 # Network packet capture
      zeek                    # Network security behavioral analyzer
      tcpflow                 # Flow recorder
      ngrep                   # Network grep

      # ------------------------------------------------------------------------
      # Optical Media, NVMe & Hardware Acquisition
      # ------------------------------------------------------------------------
      dvdplusrwtools          # DVD/BD mastering and raw extraction
      cdrtools                # CD/DVD reading tools (readcd, cdda2wav)
      safecopy                # Resilient data rescue for damaged optical / flash media
      f3                      # Fight Flash Fraud (detect fake capacity flash drives)
      nvme-cli                # NVMe health, namespaces, and vendor diagnostics
      hdparm                  # SATA drive parameters, security freeze & firmware info
      sdparm                  # SCSI/SAS disk parameter inspection
      sg3_utils               # Low-level SCSI generic command sender
      lsscsi                  # List SCSI/SATA/SAS bus topologies

      # ------------------------------------------------------------------------
      # Mobile & Firmware
      # ------------------------------------------------------------------------
      binwalk                 # Firmware extraction and analysis
      android-tools           # ADB & Fastboot for mobile extraction
      libimobiledevice        # iOS device communication utilities

      # ------------------------------------------------------------------------
      # Hardware Triage & System Utilities
      # ------------------------------------------------------------------------
      smartmontools           # SMART disk health inspection
      parted                  # Partition editor
      gptfdisk                # GPT partition editor
      pciutils                # lspci
      usbutils                # lsusb
      dmidecode               # Hardware DMI/SMBIOS decoder
      dfinfo                  # Forensic system triage & fastfetch report exporter
      lsof                    # List open files
      file                    # File magic type identification
      ripgrep                 # Fast pattern searching
      tmux                    # Terminal multiplexer
      fastfetch               # System banner
      htop                    # Process viewer
      btop                    # Modern visual monitor
      yazi                    # Fast terminal file manager
    ];
  };
}
