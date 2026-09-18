# df-nix 🔍💿
> **Declarative, Bit-for-Bit Reproducible Live NixOS Distribution Engineered for Digital Forensics and Incident Response (DFIR) Field Operations.**

`df-nix` is a specialized, air-gapped, live bootable NixOS ISO tailored for digital forensic field acquisition, damaged media triage, and incident response. It integrates **[`dfdisk`](https://github.com/tylerstyle/dfdisk)** with an asymmetric, NIST CFTT-compliant software write-blocking architecture, a dual desktop environment featuring **Niri + Noctalia** (Wayland) alongside a lightweight **XFCE** (X11) fallback, and a dedicated **`df-mount`** forensic storage manager.

---

## ⚡ Core Highlights

- **5-Layer Defense-in-Depth Write-Blocking**:
  - **Kernel Parameter Neutralization**: `systemd.gpt_auto=0` disables auto-mounting of root, home, and swap partitions from GPT evidence drives.
  - **Swap Inactivation**: `systemd.targets.swap.enable = false` ensures evidence disks with swap flags are never touched as virtual memory.
  - **Kernel Driver Ro-Enforcement**: Immediate `blockdev --setro` and `ATTR{ro}="1"` triggered via udev upon disk/partition insertion.
  - **Udisks & Polkit Lockdown**: Suppresses auto-probing and blocks unauthenticated desktop mounts.
  - **Zero Journal Replay (`df-mount`)**: Mounts ext4 (`ro,noload`), XFS (`ro,norecovery`), and Btrfs (`ro,rescue=nologreplay`) without altering filesystem superblocks or dirty logs.
- **Asymmetric Evidence vs. Target Workflow**:
  - All attached devices are locked **Read-Only** by default.
  - Examiners can selectively **unblock destination drives** or mount them writeable under `/media/target` so `dfdisk` can write `.E01` or `.raw` images.
- **Dual Desktop Experience**:
  - **Primary**: **Niri** (modern scrollable-tiling Wayland compositor) with the **Noctalia** top bar and shell, customized dark theme, and high-DPI fluidity.
  - **Top Bar Integration**: Direct access to `dfdisk` and the `df-mount-gui` forensic storage manager.
  - **Fallback**: **XFCE** (X11) with automounting strictly disabled, providing guaranteed boot on vintage laptops, legacy BIOS, or GPUs without Wayland support.
  - **Desktop Branding**: Pre-configured with the custom `DF_K-BG02.png` forensic wallpaper and auto-login to session `niri`.
- **Field-Ready Live Architecture**:
  - **`copytoram` Boot Mode**: The SquashFS image decompresses entirely into RAM during early boot. Once loaded, **the bootable USB drive can be safely ejected**, completely freeing up the USB bus for high-throughput evidence imaging.
  - **`zstd -Xcompression-level 19`**: Delivers decompression throughput exceeding 1.5 GB/s, drastically cutting boot times.
  - **100% Air-Gapped Offline Usability**: Zero runtime network dependencies. Manpages and documentation are pre-indexed for offline lookup (`man -k`).

---

## 📐 Project Architecture

```
df-nix/
├── flake.nix                       # Flake entrypoint: builds live ISO & workstation closures
├── .gitignore
├── README.md
├── modules/
│   ├── hardware/
│   │   └── write-blocking.nix      # 5-Layer udev, blockdev, swap, and daemon lockdown
│   ├── forensics/
│   │   └── default.nix             # Complete DFIR tool suites (imaging, carving, memory, pcap)
│   ├── desktop/
│   │   ├── niri.nix                # Primary Niri + Noctalia Wayland desktop environment
│   │   ├── xfce.nix                # Fallback XFCE4 X11 desktop environment (no automounting)
│   │   └── display-manager.nix     # SDDM with Wayland support & autologin to Niri
│   └── iso/
│       └── live-iso.nix            # copytoram, zstd-19, hybrid UEFI/BIOS boot, offline docs
├── pkgs/
│   ├── df-mount/                   # Forensic Mounter & Target Unblocker Suite
│   │   ├── default.nix             # Nix derivation wrapping CLI & Libadwaita GUI
│   │   ├── df-mount.sh             # Zero-journal-write CLI mount & unblock engine
│   │   └── df-mount-gui.py         # Modern GTK4 / Libadwaita graphical manager
│   ├── dwarf2json/
│   │   └── default.nix             # Volatility 3 ISF table generator
│   └── regripper/
│       └── default.nix             # Windows Registry hive artifact extractor
└── configs/
    ├── niri/
    │   ├── config.kdl              # Niri configuration with Mod+D (dfdisk) & Mod+M (dfmount)
    │   └── noctalia.kdl            # Noctalia theme color definitions
    ├── noctalia/
    │   └── settings.json           # Top bar widgets, pinned apps & wallpaper configuration
    └── assets/
        ├── wallpaper.png           # DF_K-BG02.png forensic desktop wallpaper
        ├── dfdisk.desktop          # Application launcher entry for dfdisk
        └── df-mount-gui.desktop    # Application launcher entry for df-mount-gui
```

---

## 🛠️ The df-nix Forensic Workflow

```
[Connect Suspect Media]
           │
           ▼
[udev intercepts event]
           ├── Sets sysfs ATTR{ro}="1"
           ├── Sets blockdev --setro /dev/sdb
           ├── Tags ENV{UDISKS_IGNORE}="1"
           └── Result: EVIDENCE STRICTLY WRITE-BLOCKED (Driver Level)
                   │
                   ▼
[Connect Destination Drive (e.g. /dev/sdc for E01 dumps)]
           │
           ▼
[Launch df-mount (Top Bar Icon or Mod+M)]
           │
           ├── Select Destination Drive (/dev/sdc1)
           ├── Click "💾 Mount Target" (or run 'sudo df-mount target /dev/sdc1')
           └── Destination mounted writeable at /media/target/sdc1
                   │
                   ▼
[Launch dfdisk (Top Bar Icon or Mod+D)]
           │
           ├── Source: /dev/sdb (Read-only protected evidence)
           ├── Output: /media/target/sdc1/cases/2026/
           └── Perform E01 acquisition, damaged rescue with ddrescue, or conversion
```

---

## 🧰 Bundled DFIR Tool Suite

| Category | Tools Included |
| :--- | :--- |
| **Disk Acquisition & Imaging** | `dfdisk`, `df-mount`, `libewf` (`ewfacquire`, `ewfexport`), `dcfldd`, `ddrescue`, `ddrescueview`, `afflib`, `qemu-utils` (`qemu-nbd`) |
| **Filesystem & File Carving** | `sleuthkit` (TSK), `testdisk`, `qphotorec`, `foremost`, `scalpel`, `bulk_extractor`, `ext4magic`, `extundelete` |
| **Decryption & Filesystems** | `cryptsetup` (LUKS), `dislocker` (BitLocker), `libbde`, `veracrypt`, `apfs-fuse`, `apfsprogs`, `ntfs3g`, `btrfs-progs`, `xfsprogs` |
| **Memory Forensics** | `volatility3`, `dwarf2json` |
| **Registry & Artifacts** | `regripper` (rip.pl), `chainsaw` (EVTX), `python3Packages.evtx`, `sqlitebrowser` |
| **Network Forensics** | `wireshark`, `tshark`, `tcpdump`, `zeek`, `tcpflow`, `ngrep` |
| **Mobile & Firmware** | `binwalk`, `android-tools` (ADB/Fastboot), `libimobiledevice` |
| **Hardware & Triage** | `smartmontools`, `parted`, `gptfdisk`, `pciutils`, `usbutils`, `btop`, `yazi`, `fastfetch` |

---

## 🚀 Building & Testing the Live ISO

### 1. Build the Bootable ISO
From the project root:
```bash
nix build .#iso
```
*The resulting bootable hybrid ISO will be written to `./result/iso/df-nix-forensics-x86_64-linux.iso`.*

### 2. Test in QEMU with a Simulated Evidence Disk
To verify write-blocking behavior without touching physical hardware:
```bash
# Create a dummy evidence disk image
qemu-img create -f raw test-evidence.raw 1G
mkfs.ext4 -F test-evidence.raw

# Launch live ISO in QEMU
qemu-system-x86_64 \
  -m 8G \
  -enable-kvm \
  -cpu host \
  -smp 4 \
  -cdrom ./result/iso/*.iso \
  -boot d \
  -drive file=test-evidence.raw,format=raw,if=virtio
```

Inside the booted live desktop:
```bash
# Check read-only state (should return 1)
blockdev --getro /dev/vda

# Confirm that raw writes fail immediately:
sudo dd if=/dev/zero of=/dev/vda bs=512 count=1
# Output: dd: failed to open '/dev/vda': Read-only file system
```

### 3. Flash to USB Media
```bash
sudo dd if=./result/iso/*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```
*(Replace `/dev/sdX` with your target flash drive)*

---

## ⌨️ Desktop Keybindings (Niri)

| Keybinding | Action |
| :--- | :--- |
| `Mod+D` | Launch **dfdisk** Forensic Imager in Kitty (with sudo) |
| `Mod+M` | Launch **df-mount** Forensic Storage Manager GUI |
| `Mod+Space` | Toggle Noctalia Application Launcher |
| `Mod+S` | Toggle Noctalia Control Center |
| `Mod+Return` | Launch Kitty Terminal |
| `Mod+E` | Launch Dolphin File Manager |
| `Mod+B` | Launch Firefox |
| `Mod+Shift+E` | Session Menu / Logout (switch to XFCE fallback) |

---

## 📜 License & Compliance

Distributed under the **MIT License**. Engineered according to NIST Computer Forensic Tool Testing (CFTT) write-blocking principles.
