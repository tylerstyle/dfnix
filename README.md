# dfnix 🔍💿
> **Declarative, Bit-for-Bit Reproducible Live NixOS Distribution Engineered for Digital Forensics and Incident Response (DFIR) Field Operations.**

`dfnix` is a specialized, air-gapped, live bootable NixOS ISO tailored for digital forensic field acquisition, damaged media triage, and incident response. It integrates **[`dfdisk`](https://github.com/tylerstyle/dfdisk)** with an asymmetric, NIST CFTT-compliant software write-blocking architecture, a dual desktop environment featuring **Niri + Noctalia** (Wayland) alongside a lightweight **XFCE** (X11) fallback, and dedicated standalone tools: **`dfmount`** (storage manager) and **`dfnet`** (network operations).

---

## ⚡ Core Highlights

- **5-Layer Defense-in-Depth Write-Blocking**:
  - **Kernel Parameter Neutralization**: `systemd.gpt_auto=0` disables auto-mounting of root, home, and swap partitions from GPT evidence drives.
  - **Swap Inactivation**: `systemd.targets.swap.enable = false` ensures evidence disks with swap flags are never touched as virtual memory.
  - **Kernel Driver Ro-Enforcement**: Immediate `blockdev --setro` and `ATTR{ro}="1"` triggered via udev upon disk/partition insertion.
  - **Udisks & Polkit Lockdown**: Suppresses auto-probing and blocks unauthenticated desktop mounts.
  - **Zero Journal Replay (`dfmount`)**: Mounts ext4 (`ro,noload`), XFS (`ro,norecovery`), and Btrfs (`ro,rescue=nologreplay`) without altering filesystem superblocks or dirty logs.
- **Asymmetric Evidence vs. Target Workflow**:
  - All attached devices are locked **Read-Only** by default.
  - Examiners can selectively **unblock destination drives** or mount them writeable under `/media/target` so `dfdisk` can write `.E01` or `.raw` images.
- **Dual Desktop Experience**:
  - **Primary**: **Niri** (modern scrollable-tiling Wayland compositor) with the **Noctalia** top bar and shell, customized dark theme, and high-DPI fluidity.
  - **Top Bar & TUI Integration**: Instant keyboard-driven access to `dfdisk`, `dfmount`, and `dfnet`.
  - **Fallback**: **XFCE** (X11) with automounting strictly disabled, providing guaranteed boot on vintage laptops, legacy BIOS, or GPUs without Wayland support.
  - **Desktop Branding**: Pre-configured with the custom `DF_K-BG02.png` forensic wallpaper and auto-login to session `niri`.
- **Field-Ready Live Architecture**:
  - **`copytoram` Boot Mode**: The SquashFS image decompresses entirely into RAM during early boot. Once loaded, **the bootable USB drive can be safely ejected**, completely freeing up the USB bus for high-throughput evidence imaging.
  - **`zstd -Xcompression-level 19`**: Delivers decompression throughput exceeding 1.5 GB/s, drastically cutting boot times.
  - **100% Air-Gapped Offline Usability**: Zero runtime network dependencies. Manpages and documentation are pre-indexed for offline lookup (`man -k`).

---

## 📐 Project Architecture

```
dfnix/
├── configuration.nix               # Root flakeless NixOS live ISO configuration
├── default.nix                     # Flakeless build entrypoint (nix-build -A iso)
├── Makefile                        # Single-command shortcuts (make iso, make check)
├── flake.nix                       # Optional flake definition
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
    │   ├── config.toml             # Noctalia shell configuration, top bar custom buttons, launcher
    │   └── settings.toml           # Noctalia state & wallpaper presets
    └── assets/
        ├── wallpaper.png           # DF_K-BG02.png forensic desktop wallpaper
        ├── dfdisk.desktop          # Application launcher entry for dfdisk
        ├── dfmount.desktop         # Application launcher entry for dfmount
        └── dfnet.desktop           # Application launcher entry for dfnet
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
[Launch dfmount (Top Bar Icon or Mod+M)]
           │
           ├── Select Destination Drive (/dev/sdc1)
           ├── Click "💾 Mount Target" (or run 'sudo dfmount target /dev/sdc1')
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
| **Disk Acquisition & Imaging** | `dfdisk`, `dfmount`, `libewf` (`ewfacquire`, `ewfexport`), `dcfldd`, `ddrescue`, `ddrescueview`, `afflib`, `qemu-utils` (`qemu-nbd`) |
| **Filesystem & File Carving** | `sleuthkit` (TSK), `testdisk`, `testdisk-qt`, `foremost`, `scalpel`, `bulk_extractor`, `ext4magic`, `extundelete` |
| **Decryption & Filesystems** | `cryptsetup` (LUKS), `dislocker` (BitLocker), `libbde`, `veracrypt`, `apfs-fuse`, `apfsprogs`, `ntfs3g`, `btrfs-progs`, `xfsprogs` |
| **Memory Forensics** | `volatility3`, `dwarf2json` |
| **Registry & Artifacts** | `regripper` (rip.pl), `chainsaw` (EVTX), `python3Packages.evtx`, `sqlitebrowser` |
| **Network & Acquisition** | `dfnet`, `macchanger`, `wireshark`, `tshark`, `tcpdump`, `zeek`, `cifs-utils`, `nfs-utils`, `sshfs`, `rclone` |
| **Optical Media & Hardware** | `dvdplusrwtools`, `cdrtools`, `safecopy`, `f3`, `nvme-cli`, `hdparm`, `sdparm`, `sg3_utils`, `lsscsi` |
| **Mobile & Firmware** | `binwalk`, `android-tools` (ADB/Fastboot), `libimobiledevice` |
| **Hardware & Triage** | `smartmontools`, `parted`, `gptfdisk`, `pciutils`, `usbutils`, `btop`, `yazi`, `fastfetch` |

---

## 🚀 Building, Fast Prototyping & Virtualization

`dfnix` supports two development workflows:
1. **Lightning-Fast Prototyping (`make vm`)**: Skips squashfs `zstd` compression and ISO generation entirely. Rebuilds and boots in seconds by mounting the host `/nix/store` directly via VirtIO-9p.
2. **Production ISO Release (`make iso`)**: Generates the complete, bootable, air-gapped hybrid UEFI/BIOS ISO with `zstd` squashfs compression.

---

### ⚡ 1. Fast Prototyping Workflow (`make vm`)

When iterating on desktop configurations (`niri`, `noctalia`, `starship`), udev rules, or forensic packages, compressing multiple gigabytes of squashfs after every change is slow. Use the VM target instead:

```bash
# 1. Build the instant VM closure (takes seconds)
make vm
# or flakeless: nix-build -A vm -o result-vm
# or flake:     nix build .#vm

# 2. Launch the VM
make test-vm
# or: ./scripts/run-vm.sh --vm
```

---

### 🖥️ 2. Virtualization on Workstation (`hpfury`) vs. Server (`hp-nix`)

The integrated runner `./scripts/run-vm.sh` automatically detects the host environment and configures optimal display and input drivers:

#### A. Interactive Desktop Workstation (`hpfury` / `nixos_df_r`)
When executed within an active Wayland or X11 session:
- **Display**: Automatically launches a native GUI window using hardware KVM acceleration (`-vga virtio`).
- **Cursor**: Seamless pointer capture and release via `-device usb-tablet`.
- **Drives**: Automatically attaches both a simulated suspect evidence drive (`test-evidence.raw`, write-blocked) and a destination storage drive (`test-target.raw`, writable for `dfmount` and `dfdisk`).

```bash
# Launch rapid prototyping VM in native GUI window:
make test-vm

# Or test the built ISO image in native GUI window:
make test-qemu
```

#### B. Headless Application Server (`hp-nix` / Remote SSH)
When run over SSH on a headless server without `$DISPLAY`:
- **Auto-Headless**: Automatically starts **SPICE** (port `5930`), **VNC** (port `5901`), and guest **SSH forwarding** (port `2222`).
- **Zero GUI Crashing**: Will never fail with display errors.

```bash
# Launch on hp-nix (runs in headless mode automatically):
make test-vm
# or for the full ISO:
make test-qemu
# or explicitly force headless:
make test-headless
```

##### Connecting to the VM on `hp-nix` from `hpfury`:
- **Option 1: SPICE (Recommended — dynamic resolution, clipboard & audio)**:
  ```bash
  remote-viewer spice://hp-nix:5930
  ```
- **Option 2: VNC**:
  ```bash
  vncviewer hp-nix:5901
  ```
- **Option 3: SSH Tunneling (if ports are firewalled)**:
  ```bash
  ssh -L 5901:127.0.0.1:5901 -L 5930:127.0.0.1:5930 hp-nix
  # Then locally on hpfury:
  remote-viewer spice://127.0.0.1:5930
  ```
- **Option 4: Direct SSH Console Triage (No GUI required)**:
  ```bash
  ssh -p 2222 nixos@hp-nix
  # Inside guest: passwordless sudo for dfdisk, dfmount, dfnet
  sudo dfdisk
  ```

---

### 💿 3. Building & Flashing the Live ISO

#### A. Build the Bootable ISO
```bash
make iso
# or: nix-build -A iso -o result-iso
```
*The resulting bootable hybrid ISO will be written to `./result-iso/iso/dfnix-forensics-x86_64-linux.iso`.*

#### B. Verify Write-Blocking in QEMU
Inside any booted live environment:
```bash
# Verify kernel/blockdev write-block flag (returns 1 for read-only)
blockdev --getro /dev/vda

# Confirm that raw disk writes fail immediately:
sudo dd if=/dev/zero of=/dev/vda bs=512 count=1
# Output: dd: failed to open '/dev/vda': Read-only file system
```

#### C. Flash to Physical USB Drive
```bash
# Flash with built-in safety checks against overwriting system disks:
make flash DEV=/dev/sdX
# or manually:
sudo dd if=result-iso/iso/*.iso of=/dev/sdX bs=4M status=progress conv=fsync oflag=direct
```
*(Replace `/dev/sdX` with your target USB thumbdrive)*

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
