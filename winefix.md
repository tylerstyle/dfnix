# X-Ways Forensics on Linux: Hardware Dongle Passthrough & Wine PE Patch Architecture

> **Technical deep dive into running portable X-Ways Forensics under Wine on Linux with physical USB hardware security dongles (Feitian Rockey4ND & Wibu-Systems CodeMeter), raw physical drive mapping, and memory-safe PE patching.**

---

## 1. Overview & Operational Goals

Forensic examiners frequently rely on **X-Ways Forensics** for triage, disk imaging, filesystem parsing, and file carving. While native Linux tools (`dfdisk`, `ewfacquire`, `sleuthkit`) cover core imaging and acquisition workflows, having access to portable X-Ways inside an air-gapped live triage environment allows examiners to apply familiar analysis routines directly without rebooting into Windows.

Achieving full operational parity under Wine on a live Linux distribution requires resolving four core challenges:
1. **Physical Security Dongle Recognition**: Supporting USB hardware security dongles (Feitian Rockey4ND and Wibu-Systems CodeMeter) without proprietary Windows kernel drivers.
2. **Direct Raw Physical Disk Access**: Exposing block devices (`/dev/sda`, `/dev/nvme0n1`) directly to Wine as raw physical devices (`\\.\PhysicalDriveX`).
3. **Write Permissions to Evidence Targets**: Ensuring case files, temporary databases, and carved data can be written to `/media/target` (which is mounted and managed by root).
4. **Wayland Window Management**: Handling multi-window dialogs, progress bars, and tooltips in a modern Wayland tiling compositor (Niri).

---

## 2. Root Cause Analysis: The Feitian Rockey4ND Dongle Hang

### The Symptom
When connecting a Feitian Technologies Rockey4ND USB dongle (`USB VID:PID 096e:0006`) and launching `xwforensics64.exe` under standard, unmodified Wine releases:
- The Linux kernel enumerates the device correctly as `/dev/hidrawX`.
- Wine's `winebus.sys` subsystem attaches to the HID raw node without error.
- However, X-Ways hangs upon startup and displays a recurring modal dialog:
  ```text
  "Waiting for dongle..."
  ```
  failing to initialize the software license.

### The USB HID Communication Trace
Tracing the execution through `WINEDEBUG=+hid,+hidclass,+plugplay` revealed the exact failure sequence:

1. **Enumeration & Device Handle**:
   `winebus.sys` exposes the Rockey4ND device handle via `hidclass.sys`. The Rockey4ND security library inside X-Ways opens `\\?\hid#vid_096e&pid_0006...`.
2. **Feature Report Initiation**:
   X-Ways issues an initial query (`0x38` - Find Dongle) via `HidD_SetFeature()`.
3. **The Flush Call (`HidD_FlushQueue`)**:
   Immediately after writing the feature report, the Rockey4ND communication library calls:
   ```c
   BOOLEAN HidD_FlushQueue(HANDLE HidDeviceObject);
   ```
   This routine purges stale input reports from the operating system's internal HID driver queue before reading the cryptographic challenge-response.
4. **The Missing IOCTL**:
   Inside Wine's `dlls/hid/main.c`, `HidD_FlushQueue` translates into an I/O Control request sent to the underlying PDO:
   ```c
   DeviceIoControl(HidDeviceObject, IOCTL_HID_FLUSH_QUEUE, ...);
   // IOCTL_HID_FLUSH_QUEUE = 0x000b0197
   ```
   In upstream Wine (`dlls/hidclass.sys/pdo.c`), function code `65` (`IOCTL_HID_FLUSH_QUEUE`) was **unimplemented**, dropping into the fallback default branch:
   ```text
   fixme:hid:pdo_ioctl Unsupported ioctl 0xb0197 (device=b access=0 func=65 method=3)
   ```
   The driver completes the IRP with `STATUS_NOT_SUPPORTED` (`0xc00000bb`).
5. **Communication Abort**:
   Because `HidD_FlushQueue()` returns `FALSE` (`0`), the Rockey4ND SDK assumes the hardware communication channel has encountered a fatal transport error. It aborts after 4 retries, closes the device handle, and triggers the modal prompt:
   ```text
   "Waiting for dongle..."
   ```

---

## 3. Why Standard Workarounds Failed

1. **Prefix DLL Overrides (`WINEDLLOVERRIDES="hid=n,b"`)**:
   Wine hardcodes its compile-time library directory (`dll_dir`, e.g., `/nix/store/...-wine-wow64/lib/wine`) at index 0 of `dll_paths` in `ntdll.so`. Wine's loader resolves builtin PE DLLs directly from `/lib/wine/x86_64-windows/` rather than the prefix's `drive_c/windows/system32/`. Overriding `hid=n` causes Wine to reject the DLL or fail with `STATUS_DLL_NOT_FOUND` (`0xc0000135`).
2. **Full Source Recompilation**:
   Rebuilding `wineWow64` with a source patch inside Nix requires compiling the full Wine source tree (~45–60 minutes), adding multi-gigabyte build overhead and breaking rapid declarative iteration.

---

## 4. The dfnix Solution: Dynamic PE Patcher & Isolated Mount Namespace

`dfnix` implements an architectural solution in `modules/forensics/wine-xways.nix` that operates in **under 2 seconds** with **zero disk mutations**.

### Step 1: Dynamic PE Export Table Patching (`pePatchScript`)
A lightweight Python derivation parses the portable executable (PE) structures of Wine's official precompiled `hid.dll` for both 64-bit and 32-bit:
1. Decodes PE headers and Section Headers (`.text`, `.rdata`, `.edata`).
2. Traverses Data Directory Entry 0 (Export Directory Table) to inspect the exported function names.
3. Locates the ASCII symbol `"HidD_FlushQueue"`.
4. Obtains its export ordinal and computes the file offset of its entry point.
5. Overwrites the entry point with immediate `TRUE` (`1`) return opcodes:
   - **64-bit (`x86_64`)**:
     ```assembly
     mov eax, 1    ; b8 01 00 00 00
     ret           ; c3
     ```
   - **32-bit (`i386` stdcall)**:
     ```assembly
     mov eax, 1    ; b8 01 00 00 00
     ret 4         ; c2 04 00 (clean up 1 argument)
     ```

Since this only patches the precompiled DLL from the Nix binary cache, derivation build time is **< 2 seconds**.

### Step 2: Isolated Mount Namespace (`unshare -m`)
NixOS guarantees that `/nix/store` paths are immutable. Modifying the original `hid.dll` on disk is impossible and violates system integrity.

Instead, the `xways` wrapper launches inside a private Linux mount namespace:
```bash
unshare -m --propagation private /bin/bash ...
```
Inside this ephemeral namespace, the launcher bind-mounts the patched DLLs directly over Wine's PE files in `/nix/store`:
```bash
mount --bind "$PATCHED_HID64" "$WINE_DIR/lib/wine/x86_64-windows/hid.dll"
mount --bind "$PATCHED_HID32" "$WINE_DIR/lib/wine/i386-windows/hid.dll"
```
- **Zero Host Mutation**: The underlying `/nix/store` on disk remains completely untouched and read-only.
- **Process Isolation**: The bind-mount exists only within the memory namespace of the `xways` process hierarchy and vanishes immediately upon exit.

### Step 3: Verified Cryptographic Handshake
With `HidD_FlushQueue` returning `TRUE`, the Rockey4ND SDK proceeds smoothly to the cryptographic challenge-response exchange:
```text
HidD_SetFeature  -> 0x38 (Challenge query)
HidD_GetFeature  -> 0x5a 0x00 0x00 0x00 0x00 (Authentication Success)
```
X-Ways Forensics launches instantly with full license verification.

---

## 5. Privilege Elevation & Raw Physical Drive Mapping

### Auto-Elevation with Graphical Session Preservation
Accessing raw block devices (`/dev/sda`, `/dev/nvme0n1`) and writing to evidence destination paths under `/media/target` requires root privileges.

If invoked by an unprivileged user, `xways` transparently elevates to `root` via `sudo` while preserving:
- `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` (for native Wayland rendering)
- `DISPLAY`, `XAUTHORITY`, and `xhost +si:localuser:root` (for X11 / Xwayland rendering)

### Raw Disk Block Mapping (`\\.\PhysicalDriveX`)
At startup, `xways` inspects all physical block devices detected in `/sys/block/*` and populates Wine's `dosdevices` directory:
- `d:: -> /dev/sda`
- `f:: -> /dev/sdb`
- `g:: -> /dev/nvme0n1`

Inside X-Ways, navigating to **File -> Open Drive / Physical Device** allows examiners to open, inspect, hash, or clone physical evidence drives directly through Wine.

### Convenience Drive Mappings
- `t:` -> `/media/target` (Destination evidence storage)
- `e:` -> `/media/evidence` (Mounted suspect media)
- `r:` -> `/run/media` (Removable media)
- `c:` -> `/root/.wine/drive_c` (Wine virtual C: drive)
- `z:` -> `/` (Host root filesystem)

---

## 6. Window Management in Niri (Wayland Tiling)

Under tiling window managers, Windows applications can scatter tooltips, dialogs, and progress bars into new tiled columns. `dfnix` provides two ergonomic options:

### Option 1: Native Floating Rules (Default)
In [`configs/niri/config.kdl`](file:///home/df/git/dfnix/configs/niri/config.kdl):
```kdl
window-rule {
    match app-id=r#"^xwforensics.*"# title=r#"^(?!X-Ways Forensics).+"#
    open-floating true
}
```
The main forensic workbench occupies a full-height column, while all secondary windows (Directory Browser Options, Volume Snapshot, Search, Progress dialogs) float above it automatically.

### Option 2: Wine Virtual Desktop Mode (`--desktop` / `-d`)
For examiners who prefer an isolated, classic Windows desktop window:
```bash
xways --desktop
```
This encapsulates all dialogs, context menus, and hover popups inside a single containment window, auto-scaled to the active monitor resolution.
