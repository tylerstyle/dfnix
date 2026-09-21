# dfnix 🔍💿
> **Live NixOS distribution for Digital Forensics and Incident Response (DFIR).**

`dfnix` is an offline, bootable NixOS live system built for forensic imaging, media triage, and incident response. It integrates **[`dfdisk`](https://github.com/tylerstyle/dfdisk)** with software write-blocking, a dual desktop environment featuring **Niri + Noctalia** (Wayland) alongside an **XFCE** (X11) fallback, and standalone helper tools: **`dfmount`** (storage manager), **`dfnet`** (network operations), and **`dfinfo`** (system triage).

---

## ⚡ Core Features

- **5-Layer Write Blocking**:
  - **Kernel Parameters**: `systemd.gpt_auto=0` disables automatic mounting of partitions from GPT evidence drives.
  - **Swap Disabled**: `systemd.targets.swap.enable = false` ensures evidence partitions with swap type UUIDs are not mounted as virtual memory.
  - **Read-Only Block Devices**: udev rules enforce `blockdev --setro` and `ATTR{ro}="1"` upon device insertion.
  - **Udisks & Polkit Restrictions**: Disables automount probing and blocks unauthenticated desktop mounts.
  - **No Journal Replay (`dfmount`)**: Mounts ext4 (`ro,noload`), XFS (`ro,norecovery`), and Btrfs (`ro,rescue=nologreplay`) without modifying filesystems.
- **Evidence vs. Target Storage**:
  - Attached devices are set to **Read-Only** by default.
  - Destination drives can be selectively unblocked and mounted writeable under `/media/target` for `.E01` or raw disk images.
- **Desktop Environments**:
  - **Primary**: **Niri** (scrollable-tiling Wayland compositor) with the **Noctalia** top bar and launcher.
  - **Direct Shortcuts**: Keybindings to launch `dfdisk`, `dfmount`, `dfnet`, and `dfinfo`.
  - **Fallback**: **XFCE** (X11) with automounting disabled, for hardware without Wayland support or legacy BIOS.
  - **Theming**: Digital forensics wallpapers with automated rotation and adaptive colors.
- **Live System Architecture**:
  - **`copytoram` Boot Mode**: The SquashFS image is copied into RAM during boot, allowing the boot USB drive to be removed after startup to free the USB bus.
  - **`zstd` Compression**: Compressed with `zstd -Xcompression-level 19` for fast decompression and shorter boot times.
  - **Offline Operation**: No runtime network dependencies. Documentation and manual pages are pre-indexed for offline access (`man -k`).

---

## 📐 Project Architecture

```
dfnix/
├── configuration.nix               # Root flakeless NixOS live ISO configuration
├── default.nix                     # Flakeless build entrypoint (nix-build -A iso)
├── Makefile                        # Build shortcuts (make iso, make check, make vm)
├── flake.nix                       # Optional flake definition
├── .gitignore
├── README.md
├── winefix.md                      # Technical documentation for X-Ways Wine HID patch
├── modules/
│   ├── hardware/
│   │   └── write-blocking.nix      # 5-Layer udev, blockdev, swap, and daemon rules
│   ├── forensics/
│   │   └── default.nix             # DFIR tool suites (imaging, carving, memory, network)
│   ├── desktop/
│   │   ├── niri.nix                # Primary Niri + Noctalia Wayland desktop environment
│   │   ├── xfce.nix                # Fallback XFCE4 X11 desktop environment (no automounting)
│   │   └── display-manager.nix     # SDDM with Wayland support & autologin to Niri
│   └── iso/
│       └── live-iso.nix            # copytoram, zstd-19, hybrid UEFI/BIOS boot, offline docs
├── pkgs/
│   ├── df-mount/                   # Forensic Mounter & Target Unblocker
│   │   ├── default.nix             # Nix derivation wrapping CLI & Libadwaita GUI
│   │   ├── df-mount.sh             # CLI mount & unblock script
│   │   └── df-mount-gui.py         # GTK4 / Libadwaita graphical manager
│   ├── dfinfo/                     # Forensic System Triage & Fastfetch Suite
│   ├── dfnix-guide/                # Interactive Quick Start Guide & Cheat Sheet
│   ├── dwarf2json/
│   │   └── default.nix             # Volatility 3 ISF table generator
│   └── regripper/
│       └── default.nix             # Windows Registry hive artifact extractor
└── configs/
    ├── niri/
    │   ├── config.kdl              # Niri configuration with Mod+D (dfdisk) & Mod+M (dfmount)
    │   └── noctalia.kdl            # Noctalia theme color definitions
    ├── noctalia/
    │   ├── config.toml             # Noctalia shell configuration, top bar buttons, launcher
    │   └── settings.toml           # Noctalia state & wallpaper settings
    └── assets/
        ├── wallpapers/             # Digital forensics wallpapers with automated rotation
        ├── dfdisk.desktop          # Application launcher entry for dfdisk
        ├── dfmount.desktop         # Application launcher entry for dfmount
        ├── dfnet.desktop           # Application launcher entry for dfnet
        ├── dfinfo.desktop          # Application launcher entry for dfinfo
        └── dfnix-guide.desktop     # Application launcher entry for dfnix-guide
```

---

## 🛠️ Forensic Workflow

```
[Connect Suspect Media]
           │
           ▼
[udev intercepts event]
           ├── Sets sysfs ATTR{ro}="1"
           ├── Sets blockdev --setro /dev/sdb
           ├── Tags ENV{UDISKS_IGNORE}="1"
           └── Result: Evidence drive set to read-only
                   │
                   ▼
[Connect Destination Drive (e.g. /dev/sdc for E01 dumps)]
           │
           ▼
[Launch dfmount (Top Bar Icon or Mod+M)]
           │
           ├── Select Destination Drive (/dev/sdc1)
           ├── Click "Mount Target" (or run 'sudo dfmount target /dev/sdc1')
           └── Destination mounted writeable at /media/target/sdc1
                   │
                   ▼
[Launch dfdisk (Top Bar Icon or Mod+D)]
           │
           ├── Source: /dev/sdb (Read-only protected evidence)
           ├── Output: /media/target/sdc1/cases/2026/
           └── Acquire E01 image, run ddrescue, or convert images
```

---

## 🧰 DFIR Tool Suite

| Category | Tools Included |
| :--- | :--- |
| **Disk Acquisition & Imaging** | `dfdisk`, `dfmount`, `xways` (Wine launcher), `libewf` (`ewfacquire`, `ewfexport`), `dcfldd`, `ddrescue`, `ddrescueview`, `afflib`, `qemu-utils` (`qemu-nbd`) |
| **Filesystem & File Carving** | `sleuthkit` (TSK), `testdisk`, `testdisk-qt`, `foremost`, `scalpel`, `bulk_extractor`, `ext4magic`, `extundelete` |
| **Decryption & Filesystems** | `cryptsetup` (LUKS), `dislocker` (BitLocker), `libbde`, `veracrypt`, `apfs-fuse`, `apfsprogs`, `ntfs3g`, `btrfs-progs`, `xfsprogs` |
| **Memory Forensics** | `volatility3`, `dwarf2json` |
| **Registry & Artifacts** | `regripper` (rip.pl), `chainsaw` (EVTX), `python3Packages.evtx`, `sqlitebrowser` |
| **Network & Acquisition** | `dfnet`, `macchanger`, `wireshark`, `tshark`, `tcpdump`, `zeek`, `cifs-utils`, `nfs-utils`, `sshfs`, `rclone` |
| **Optical Media & Hardware** | `dvdplusrwtools`, `cdrtools`, `safecopy`, `f3`, `nvme-cli`, `hdparm`, `sdparm`, `sg3_utils`, `lsscsi` |
| **Mobile & Firmware** | `binwalk`, `android-tools` (ADB/Fastboot), `libimobiledevice` |
| **Hardware & Triage** | `smartmontools`, `parted`, `gptfdisk`, `pciutils`, `usbutils`, `btop`, `yazi`, `fastfetch` |

---

## 🍷 Portable X-Ways Forensics (Wine & Dongle Support)

`dfnix` includes a launcher and compatibility layer for portable **X-Ways Forensics** installations (`xwforensics64.exe` / `xwforensics.exe`), with **hardware dongle support** (Feitian Rockey4ND & Wibu CodeMeter) and **raw physical block device mapping**.

### 1. Usage & Auto-Discovery

Launch X-Ways from the application launcher (`X-Ways Forensics (Wine)`) or from the terminal:

```bash
# Auto-discover X-Ways on connected drives (/media/target, /media/evidence, /run/media, Desktop):
xways

# Specify the path to a portable folder:
xways /media/target/sde1/Fallvorlage_21.8_SR-4/Programm/

# Specify the executable directly:
xways /media/target/sde1/Fallvorlage_21.8_SR-4/Programm/xwforensics64.exe
```

- **Binary Selection**: Searches for `xwforensics64.exe` first, falling back to 32-bit `xwforensics.exe` or `xwinvestigator` if needed.
- **Directory Support**: Accepts directory paths or direct executable paths.

### 2. Privilege Elevation & Raw Physical Drive Mapping

- **Privilege Elevation**: When invoked by an unprivileged user, `xways` prompts for `sudo` and preserves Wayland (`WAYLAND_DISPLAY`) and X11 display credentials so the interface renders properly.
- **Target Drive Write Permissions**: External drives mounted by `dfmount` under `/media/target` are owned by `root:root`. Running as root ensures X-Ways can write case logs, temporary data, and image output.
- **Raw Disk Block Mapping (`\\.\PhysicalDriveX`)**: Physical drives attached to the system (`/dev/sda`, `/dev/sdb`, `/dev/nvme0n1`, etc.) are dynamically linked into Wine's `dosdevices` as raw physical drives (`d::`, `f::`, `g::`, etc.). In X-Ways, select **File -> Open Drive / Physical Device** to inspect or image raw media directly.
- **Drive Mappings**:
  - `t:` -> `/media/target` (Destination evidence storage)
  - `e:` -> `/media/evidence` (Mounted suspect media)
  - `r:` -> `/run/media` (Removable media)
  - `c:` -> `/root/.wine/drive_c` (Wine virtual C: drive)
  - `z:` -> `/` (Host root filesystem)

### 3. Hardware Dongle Support

Hardware security dongles (**Feitian Technologies Rockey4ND** and **Wibu-Systems CodeMeter**) are supported. Dongle communication is handled via a patched Wine HID library (`HidD_FlushQueue`) within an isolated mount namespace.

> For the root cause analysis, PE export table patching mechanics, and mount namespace implementation, see [**`winefix.md`**](file:///home/df/git/dfnix/winefix.md).

### 4. Window Management (Tiled vs. Windowed Mode)

Because Niri is a tiling compositor, Windows applications with numerous dialogs can open separate tiled columns. `dfnix` supports two modes of operation:

1. **Tiled Mode with Floating Dialogs (Default)**:
   In `configs/niri/config.kdl`, window rules match X-Ways processes. The primary forensics window opens in a tiled column, while secondary dialogs (Volume Snapshot, Directory Browser Options, Search, Progress bars) open as floating windows over the application.

2. **Windowed Mode / Virtual Desktop (`--desktop` / `-d`)**:
   In windowed mode, X-Ways runs entirely contained within a single dedicated desktop window. All sub-windows, context menus, and tooltips stay inside that single window container, preventing them from tiling:
   ```bash
   # Launch in windowed mode (auto-detects screen resolution):
   xways --desktop

   # Specify custom window resolution:
   xways --desktop=2560x1440
   # or: xways -d -r 1920x1080 /path/to/folder
   ```
   Windowed mode can also be launched directly from the Noctalia application launcher (`Mod+Space`) via **X-Ways Forensics (Virtual Desktop)**.

---

## 🚀 Building & Virtualization

`dfnix` supports two build and testing workflows:
1. **VM Prototyping (`make vm`)**: Skips squashfs compression for rapid iteration during development.
2. **ISO Build (`make iso`)**: Generates the bootable hybrid UEFI/BIOS ISO.

---

### ⚡ 1. VM Prototyping (`make vm`)

For testing desktop configurations, udev rules, or packages without waiting for squashfs compression:

```bash
# 1. Build VM
make vm
# or: nix-build -A vm -o result-vm

# 2. Launch VM
make test-vm
# or: ./scripts/run-vm.sh --vm
```

---

### 🖥️ 2. Virtualization: Desktop Workstation vs. Headless Server

The `./scripts/run-vm.sh` runner detects the host environment:

#### A. Desktop Workstation (Local GUI)
When run within an active graphical session (Wayland or X11):
- Uses hardware KVM acceleration and VirtIO graphics (`-vga virtio`).
- Captures the pointer smoothly via `-device usb-tablet`.
- Attaches test evidence (`test-evidence.raw`, read-only) and target storage (`test-target.raw`, writable).

```bash
# Test VM in a local GUI window:
make test-vm

# Test the built ISO in a local GUI window:
make test-qemu
```

#### B. Headless Server (Remote SSH)
When run over SSH without a local display:
- Starts **SPICE** (port `5930`), **VNC** (port `5901`), and guest **SSH forwarding** (port `2222`).
- Runs without requiring a host display server.

```bash
# Launch on remote server (runs headless automatically):
make test-vm
# or for the full ISO:
make test-qemu
# or force headless:
make test-headless
```

##### Connecting to Headless VM:
- **SPICE**: `remote-viewer spice://<server-ip>:5930`
- **VNC**: `vncviewer <server-ip>:5901`
- **SSH Tunnel**:
  ```bash
  ssh -L 5901:127.0.0.1:5901 -L 5930:127.0.0.1:5930 user@<server-ip>
  # Then locally on your workstation:
  remote-viewer spice://127.0.0.1:5930
  ```
- **Guest SSH Console**:
  ```bash
  ssh -p 2222 nixos@<server-ip>
  sudo dfdisk
  ```

---

### 💿 3. Building & Flashing the Live ISO

#### A. Build the Bootable ISO
```bash
make iso
# or: nix-build -A iso -o result-iso
```
*The resulting bootable hybrid ISO is written to `./result-iso/iso/dfnix-forensics.iso`.*

#### B. Verify Write-Blocking in QEMU
Inside the live system:
```bash
# Verify kernel write-block flag (returns 1 for read-only)
blockdev --getro /dev/vda

# Confirm that raw disk writes fail:
sudo dd if=/dev/zero of=/dev/vda bs=512 count=1
# Output: dd: failed to open '/dev/vda': Read-only file system
```

#### C. Flash to USB Drive
```bash
make flash DEV=/dev/sdX
# or manually:
sudo dd if=result-iso/iso/*.iso of=/dev/sdX bs=4M status=progress conv=fsync oflag=direct
```
*(Replace `/dev/sdX` with your target USB drive)*

---

## ⌨️ Desktop Keybindings (Niri)

| Keybinding | Action |
| :--- | :--- |
| `F1` / `Mod+F1` | Launch **dfnix-guide** Quick Start & Keybindings (Floating Info) |
| `Mod+D` | Launch **dfdisk** in Kitty (sudo) |
| `Mod+M` | Launch **dfmount** GUI (sudo) |
| `Mod+N` | Launch **dfnet** in Kitty (sudo) |
| `Mod+I` | Launch **dfinfo** in Kitty (sudo) |
| `Mod+Space` | Toggle Noctalia Application Launcher |
| `Mod+S` | Toggle Noctalia Control Center |
| `Mod+Return` | Launch Kitty Terminal |
| `Mod+E` | Launch Dolphin File Manager |
| `Mod+B` | Launch Firefox |
| `Mod+Shift+E` | Session Menu / Logout |

---

## 📜 License

Distributed under the **MIT License**. Follows NIST Computer Forensic Tool Testing (CFTT) write-blocking principles.
