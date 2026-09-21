# dfnix 🔍💿
> **Declarative, Bit-for-Bit Reproducible Live NixOS Distribution Engineered for Digital Forensics and Incident Response (DFIR) Field Operations.**

`dfnix` is a specialized, air-gapped, live bootable NixOS ISO tailored for digital forensic field acquisition, damaged media triage, and incident response. It integrates **[`dfdisk`](https://github.com/tylerstyle/dfdisk)** with an asymmetric, NIST CFTT-compliant software write-blocking architecture, a dual desktop environment featuring **Niri + Noctalia** (Wayland) alongside a lightweight **XFCE** (X11) fallback, and dedicated standalone tools: **`dfmount`** (storage manager), **`dfnet`** (network operations), and **`dfinfo`** (system triage & fastfetch reporting).

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
  - **Top Bar & TUI Integration**: Instant keyboard-driven access to `dfdisk`, `dfmount`, `dfnet`, and `dfinfo`.
  - **Fallback**: **XFCE** (X11) with automounting strictly disabled, providing guaranteed boot on vintage laptops, legacy BIOS, or GPUs without Wayland support.
  - **Desktop Branding**: Pre-configured with dynamic digital forensics 4K wallpapers, automated rotation, and Noctalia wallpaper-adaptive theming.
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
        ├── wallpapers/             # Curated digital forensics 4K wallpapers with automated rotation
        ├── dfdisk.desktop          # Application launcher entry for dfdisk
        ├── dfmount.desktop         # Application launcher entry for dfmount
        ├── dfnet.desktop           # Application launcher entry for dfnet
        └── dfinfo.desktop          # Application launcher entry for dfinfo
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

## 🍷 Portable X-Ways Forensics (Wine & Hardware Dongle Architecture)

`dfnix` includes an out-of-the-box launcher and compatibility layer for portable **X-Ways Forensics** installations (`xwforensics64.exe` / `xwforensics.exe`), complete with **hardware security dongle passthrough** (Feitian Rockey4ND & Wibu CodeMeter) and **raw physical block device mapping**.

### 1. Usage & Auto-Discovery

You can launch X-Ways either via the desktop application launcher / Noctalia search (`X-Ways Forensics (Wine)`), or directly from the terminal:

```bash
# Auto-discover X-Ways on connected drives (/media/target, /media/evidence, /run/media, Desktop):
xways

# Or provide the path to your portable folder:
xways /media/target/sde1/Fallvorlage_21.8_SR-4/Programm/

# Or specify the exact executable:
xways /media/target/sde1/Fallvorlage_21.8_SR-4/Programm/xwforensics64.exe
```

- **64-bit Priority**: Automatically defaults to `xwforensics64.exe` (optimal for memory-intensive evidence indexing and carving) with case-insensitive search, falling back to 32-bit `xwforensics.exe` or `xwinvestigator` if needed.
- **Folder Arguments**: Accepting folder paths directly prevents path-resolution mistakes during rapid field deployments.

### 2. Privilege Elevation & Raw Physical Drive Mapping

Forensic triage and cloning in X-Ways require unrestricted direct access to physical storage devices:
- **Auto-Elevation with Graphical Preservation**: If invoked by an unprivileged user, `xways` auto-elevates to `root` via `sudo` while transparently preserving Wayland (`WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`) and X11 (`DISPLAY`, `XAUTHORITY`, `xhost`) credentials so the GUI renders without display errors.
- **Target Drive Write Permissions**: External drives mounted by `dfmount` under `/media/target` are owned by `root:root`. Running as root ensures X-Ways has full write access for case logs, temp folders, and image output.
- **Raw Disk Block Mapping (`\\.\PhysicalDriveX`)**: Physical drives attached to the system (`/dev/sda`, `/dev/sdb`, `/dev/nvme0n1`, etc.) are dynamically linked into Wine's `dosdevices` as raw physical drives (`d::`, `f::`, `g::`, etc.). Within X-Ways, choose **File -> Open Drive / Physical Device** to inspect, hash, or clone raw media directly through Wine.
- **Convenience DOS Mappings**:
  - `t:` -> `/media/target` (Destination evidence storage)
  - `e:` -> `/media/evidence` (Mounted suspect media)
  - `r:` -> `/run/media` (Removable media)
  - `c:` -> `/root/.wine/drive_c` (Wine virtual C: drive)
  - `z:` -> `/` (Host root filesystem)

### 3. Hardware Dongle Support

Hardware security dongles (**Feitian Technologies Rockey4ND** and **Wibu-Systems CodeMeter**) are supported out of the box. Dongle detection and communication work seamlessly thanks to an automated, low-overhead PE patch for Wine's HID subsystem (`HidD_FlushQueue`) combined with ephemeral Linux mount namespaces.

> 📖 **Deep Technical Architecture**: For the full root cause analysis, PE export table patching mechanics, and mount namespace implementation, refer to the dedicated guide: [**`winefix.md`**](file:///home/df/git/dfnix/winefix.md).


### 4. Window Management in Niri (Floating Dialogs & Virtual Desktop Mode)

By default in tiling window managers, Windows applications often scatter modal dialogs, progress windows, and tooltips into separate tiled columns. `dfnix` solves this with a hybrid approach:

1. **Native Floating Rules (Default)**:
   Niri (`configs/niri/config.kdl`) is pre-configured with rules matching X-Ways (`xwforensics`, `xwinvestigator`, `winhex`). The main forensics window opens with full column width in the tiling layout, while all secondary dialogs (Volume Snapshot, Directory Browser Options, Search, Error/Warning boxes, Progress bars) automatically open as **floating windows** on top of the main application.

2. **Wine Virtual Desktop Mode (`--desktop` / `-d`)**:
   For examiners who prefer an isolated, 100% classic Windows desktop experience where all popups, context menus, and hover tooltips remain strictly contained inside a single window:
   ```bash
   # Launch in Wine Virtual Desktop (auto-detects active monitor resolution):
   xways --desktop

   # Or specify custom resolution:
   xways --desktop=2560x1440
   # or: xways -d -r 1920x1080 /path/to/folder
   ```
   A dedicated application entry **X-Ways Forensics (Virtual Desktop)** is also available directly in the Noctalia application launcher (`Mod+Space`).

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

### 🖥️ 2. Virtualization: Desktop Workstation vs. Headless Server

The integrated runner `./scripts/run-vm.sh` automatically detects the host environment and configures optimal display and input drivers:

#### A. Interactive Desktop Workstation (Local GUI)
When executed within an active Wayland or X11 session on a desktop machine:
- **Display**: Automatically launches a native GUI window using hardware KVM acceleration (`-vga virtio`).
- **Cursor**: Seamless pointer capture and release via `-device usb-tablet`.
- **Drives**: Automatically attaches both a simulated suspect evidence drive (`test-evidence.raw`, write-blocked) and a destination storage drive (`test-target.raw`, writable for `dfmount` and `dfdisk`).

```bash
# Launch rapid prototyping VM in native GUI window:
make test-vm

# Or test the built ISO image in native GUI window:
make test-qemu
```

#### B. Headless Server (Remote SSH)
When run over SSH on a headless remote server without `$DISPLAY`:
- **Auto-Headless**: Automatically starts **SPICE** (port `5930`), **VNC** (port `5901`), and guest **SSH forwarding** (port `2222`).
- **Zero GUI Crashing**: Operates without requiring an X11/Wayland display server on the host.

```bash
# Launch on remote server (runs in headless mode automatically):
make test-vm
# or for the full ISO:
make test-qemu
# or explicitly force headless:
make test-headless
```

##### Connecting to the VM on a Remote Server:
- **Option 1: SPICE (Recommended — dynamic resolution, clipboard & audio)**:
  ```bash
  remote-viewer spice://<server-ip>:5930
  ```
- **Option 2: VNC**:
  ```bash
  vncviewer <server-ip>:5901
  ```
- **Option 3: SSH Tunneling (if ports are firewalled)**:
  ```bash
  ssh -L 5901:127.0.0.1:5901 -L 5930:127.0.0.1:5930 user@<server-ip>
  # Then locally on your workstation:
  remote-viewer spice://127.0.0.1:5930
  ```
- **Option 4: Direct SSH Console Triage (No GUI required)**:
  ```bash
  ssh -p 2222 nixos@<server-ip>
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
| `Mod+M` | Launch **dfmount** Forensic Storage Manager GUI (with sudo) |
| `Mod+N` | Launch **dfnet** Forensic Network Operations in Kitty (with sudo) |
| `Mod+I` | Launch **dfinfo** Forensic System Triage & Fastfetch in Kitty (with sudo) |
| `Mod+Space` | Toggle Noctalia Application Launcher |
| `Mod+S` | Toggle Noctalia Control Center |
| `Mod+Return` | Launch Kitty Terminal |
| `Mod+E` | Launch Dolphin File Manager |
| `Mod+B` | Launch Firefox |
| `Mod+Shift+E` | Session Menu / Logout (switch to XFCE fallback) |

---

## 📜 License & Compliance

Distributed under the **MIT License**. Engineered according to NIST Computer Forensic Tool Testing (CFTT) write-blocking principles.
