# dfnix: Forensic Hardening, Architectural Review & Next Steps

**Date:** 2026-10-11  
**Status:** Architecture & Forensic Safety Audit Synthesis  
**Scope:** `dfnix` (NixOS Distribution Layer) & Standalone Forensic Tools (`dfdisk`, `dfmount`, `dfnet`)  
**Evaluation Basis:** Joint Technical Audit by Antigravity & Claude Code (`dfnix-claude`)

---

## 1. Executive Summary

`dfnix` provides a robust, reproducible NixOS distribution layer for digital forensics with an offline live environment, multi-desktop flexibility (Niri Wayland with XFCE X11 fallback), and hardware write-blocking by default. 

However, a deep forensic code audit across `dfnix` and its upstream tool repositories (`dfdisk`, `dfmount`, `dfnet`) revealed critical vulnerabilities in CLI fallbacks, edge-case handling, and daemon defaults that could inadvertently contaminate suspect media or compromise chain-of-custody before evidence reaches court.

This document lays out the exact discrepancies identified, critical forensic vulnerabilities, and a phased technical roadmap to transition `dfnix` from a functional prototype into an evidentiary-grade platform.

---

## 2. Audit Reality Matrix & Documentation Discrepancies

| Component / Claim | Documented Claim | Codebase Reality | Required Action |
| :--- | :--- | :--- | :--- |
| **`dfmount` Tests** | "Tests passing" | **0 tests implemented** (only empty test harness stub exists in `src/main.rs`). | Implement integration & unit tests for mount options and device parsing. |
| **`dfdisk` Tests** | "114 tests passing" | **186 tests passing** across engine robustness, discovery, hashing, and safety suites. | Update documentation metrics. |
| **Polkit Write Protection** | "Neutralizes filesystem-mount and drive-eject" | Rule targets `filesystem-mount` and `encrypted-unlock` only for users **outside `wheel`**. Live user `nixos` belongs to `wheel`, bypassing rule. | Update polkit rule to apply universally regardless of `wheel` membership. |
| **Air-Gap / Network** | "Offline / air-gapped by default" | NetworkManager connects automatically with DHCP using real hardware MAC (`macAddress = "preserve"`). `timesyncd` polls NTP and updates RTC. | Set random cloned MAC at boot; disable autoconnect; disable `timesyncd`. |
| **Wine Physical Drives** | "Read-only symlinks for raw disks" | Ordinary symlinks created in DOS drives. Protection solely relies on host kernel block-level read-only flag. | Clarify documentation; verify kernel read-only enforcement prior to Wine launch. |
| **Tool Packaging / Flake** | "No scripts vendored; single source of truth" | Legacy `configuration.nix`/`default.nix` builds from uncommitted local sibling folders; `pkgs/dfdisk` pins v0.1.6; `pkgs/dfmount`/`dfnet` use unpinned `fetchTarball`. | Harmonize flakeless paths to use flake-compat or exact pinned Git revisions. |

---

## 3. Critical Forensic Vulnerabilities (P0)

### 3.1. `dfmount` (`~/git/dfmount`)

1. **Unprotected CLI Subcommands:**
   - While the TUI key handlers check `is_system`, the CLI subcommands `dfmount target <dev>` and `dfmount unblock <dev>` directly invoke `blockdev --setrw` without running `is_system` verification (`src/main.rs:514-529`).
   - Any CLI script or user mistake can unblock the live root drive or connected suspect media.
2. **Whole-Disk Exposure on Partition Unblock:**
   - On Linux kernels, setting a parent block device to read-only makes all child partitions read-only. Consequently, unblocking a target partition clears the read-only flag on the entire parent disk (`src/main.rs:190-212`).
   - If a drive contains both evidence and target partitions, unblocking the target unblocks the entire drive.
   - `lsblk -rno PATH` pulls in device-mapper/md holders that can span multiple physical disks.
3. **Ignored `setro` Errors & Fall-Through Journal Replay:**
   - `let _ = blockdev --setro`: Failures during read-only enforcement are silently ignored (`src/main.rs:143-170`).
   - `blkid` runs without `-p` (low-level probing), relying on potentially stale cache.
   - Errors fall back to a generic `mount -o ro` mount. On writable mapped devices (`dm-*`, `loop*` intentionally left writable by udev for LUKS targets), a generic read-only mount of a dirty ext4/XFS filesystem triggers **journal playback**, altering evidence.
4. **NTFS Mount Parameter Incompatibility:**
   - Modern Linux kernels use `ntfs3`, which does not accept `norecover` (an `ntfs-3g` option). Forensic mounts on NTFS volumes fail or fall back improperly.
5. **Hotplug Race Condition:**
   - The TUI operates on kernel device names (`sdb`) cached during scan. If drives are swapped, keys operate on the newly attached drive without serial re-verification.

### 3.2. `dfdisk` (`~/git/dfdisk`)

1. **Silent E01 Overwrites:**
   - `ewfacquire -u` (`src/engines/ewf.rs:40`) enables automatic file overwrite without user confirmation. Drives without readable serials default to `NOSERIAL`, creating severe filename collision risks.
2. **Non-Functional Destination-on-Source Collision Check:**
   - The validation compares the canonical path of the output image *file* against the source *block device* node (`src/engines/raw.rs:84-95`). Since a regular file never equals a block special device, this check never triggers, allowing an image to be saved onto a mounted partition of the source drive being imaged.
3. **E01 Hashing Defects & Media Wear:**
   - Disabling SHA-1 or SHA-256 causes a false "HASH MISMATCH" error.
   - The default configuration re-reads the entire source disk a second time to calculate SHA-1, doubling mechanical wear on failing evidence drives.
4. **RAW Mode Error Handling:**
   - RAW engine aborts on the first read error, yet the final acquisition report claims "zero-fill completed".

### 3.3. `dfnet` (`~/git/dfnet`)

1. **Unauthenticated Raw Disk Receiver:**
   - The disk receive listener binds to `0.0.0.0:9999` and accepts the first incoming TCP connection without authentication or client verification.
   - The TUI path does not mandate `--expected-sha256`, allowing arbitrary network endpoints to push spoofed data into the target evidence store.
2. **NetworkManager Hotspot IP Forwarding Leak:**
   - The Wi-Fi hotspot uses NetworkManager `ipv4.method shared`, which activates kernel IP forwarding globally (`sysctl net.ipv4.ip_forward=1`).
   - When the hotspot shuts down, IP forwarding is never deactivated, leaving the host operating as a forwarder.
3. **Early DHCP and MAC Leakage:**
   - NetworkManager initializes during boot prior to userland `dfnet` MAC spoofing, leaking the physical MAC address and hostname `df-forensics` via DHCP to the local network.

### 3.4. `dfnix` Distribution & Host Invariants

1. **Hardware Clock (RTC) Tampering via `timesyncd`:**
   - When network connectivity is established, `systemd-timesyncd` synchronizes system time. The Linux kernel periodically syncs system time back to the suspect machine's hardware RTC every 11 minutes (`11 minute mode`), altering hardware evidence timestamps.
2. **Kernel-Level Write Blocking Limitations:**
   - `blockdev --setro` and `ATTR{ro}="1"` only restrict standard user-space file operations. Kernel internal writes (`bio_check_ro`) log warnings rather than hard-failing in certain code paths.
   - Direct raw SCSI/ATA commands (`SG_IO` ioctls) bypass block device read-only flags entirely (`hdparm`, `sg3_utils`, `nvme-cli`).
3. **Appliance Virtual Disk Exemption Race:**
   - `modules/hardware/write-blocking.nix` exempts `sda*` on VMware/VirtualBox appliances. If an attached physical or virtual evidence drive enumerates as `sda` before the OS virtual disk, the evidence drive becomes writable.
4. **Hibernation Resume Evidence Contamination:**
   - If an attached evidence disk contains a system hibernation image, kernel boot without `noresume` / `nohibernate` will attempt swap header rewrite.

---

## 4. Phased Action Plan & Technical Roadmap

```
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 0: Pre-Case Safety Critical Hotfixes (P0)                         │
│ • CLI safety guards in dfmount/dfdisk • Fix E01 overwrite & hash wear  │
│ • Disable timesyncd & fix RTC sync   • Isolate VM appliance ID_PATH    │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 1: Automated CFTT Test Harness in CI (P1)                        │
│ • Automated nixosTest VM suite with dirty ext4, XFS, NTFS, LUKS, swap   │
│ • Cryptographic hash before-and-after verification                     │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼─────────────────────────────────────┐
│ Phase 2: Architectural Consolidation & Evidentiary Audit (P2)          │
│ • Unified dfcore protected-device crate / registry                     │
│ • Append-only tamper-evident JSONL audit log                            │
│ • Refactor flake into unified modular profiles                         │
└────────────────────────────────────────────────────────────────────────┘
```

### Phase 0: Pre-Case Safety Critical Hotfixes (Immediate)

#### A. `dfmount`
* [ ] **Add `is_system` checks to CLI subcommands:** Guarantee `dfmount target` and `dfmount unblock` enforce identical protection rules as the TUI.
* [ ] **Make `blockdev --setro` failures fatal:** Abort mount operations if kernel read-only enforcement returns non-zero.
* [ ] **Low-level filesystem probing:** Use `blkid -p` and refuse mounting if filesystem type is unrecognized or ambiguous.
* [ ] **Strict Target Isolation:** Refuse to unblock any disk if it contains existing evidence partitions. Mandate typed confirmation (e.g. typing target disk name) before applying `setrw`.
* [ ] **Fix NTFS driver options:** Support `ntfs3` / `ntfs-3g` options cleanly without failing back to unshielded mounts.

#### B. `dfdisk`
* [ ] **Forbid silent E01 overwrite:** Remove `-u` flag from `ewfacquire` or explicitly check file existence beforehand.
* [ ] **Fix destination-on-source tree validation:** Resolve the backing device of the target path (via `df --output=source` or `/sys/class/block`) and verify it does not share the same root device as the source.
* [ ] **Fix dual-hash wear & false mismatches:** Stream hashes simultaneously during imaging rather than executing secondary read passes over failing disks.
* [ ] **Truthful RAW reporting:** If a read error terminates RAW acquisition, reflect exact partial status in reports instead of claiming zero-fill completion.

#### C. `dfnet`
* [ ] **Secure stream receiver:** Bind listener to a user-specified interface rather than `0.0.0.0`; mandate expected byte count and SHA-256 verification.
* [ ] **Clean IP forwarding teardown:** Restore kernel IP forwarding state when hotspot terminates; enforce strict iptables FORWARD drops.
* [ ] **Pre-DHCP MAC randomization:** Configure NetworkManager to use randomized MAC addresses before bringing interfaces up at boot (`wifi.cloned-mac-address = "random"`, `ethernet.cloned-mac-address = "random"`).

#### D. `dfnix` OS Integration
* [ ] **Disable `timesyncd`:** Prevent RTC modifications on suspect hardware.
* [ ] **Explicit kernel safety flags:** Add `noresume nohibernate` to `boot.kernelParams` in `write-blocking.nix`.
* [ ] **Stable appliance disk exemption:** Replace `sda*` matching with controller slot matching via `ENV{ID_PATH}`.
* [ ] **Universal Polkit rule:** Remove `!user.isInGroup("wheel")` exemption in `10-dfnix-write-blocking` polkit rule.

---

### Phase 1: Automated NIST CFTT Regression Test Harness (High Value)

To transform forensic write-blocking from an assertion into a verified, regression-tested property:
* [ ] **Implement `nixosTest` Framework:**
  - Build a headless QEMU test harness inside NixOS CI.
  - Generate virtual disks containing intentionally "dirty" filesystems:
    - Unclean ext4 journal
    - Unclean XFS log
    - NTFS with dirty bit set
    - LUKS container with mapped volume
    - Active MDADM RAID array member
    - Active LVM volume group
    - GPT partition table with swap signature
  - Calculate SHA-256 hashes of all raw backing disk images prior to VM boot.
  - Boot the real `dfnix` live ISO closure in the VM, attach the disks, and run `dfinfo`, `dfmount`, and `dfdisk`.
  - Shut down the VM and verify that backing disk SHA-256 hashes **remain 100% identical**.

---

### Phase 2: Architectural Consolidation & Evidentiary Traceability

* [ ] **Unified `dfcore` Shared Crate / Registry:**
  - Create a single shared definition of protected devices (live ISO, root disk, target drive) rather than maintaining 5 separate implementations across `dfdisk`, `dfmount`, and shell scripts.
  - Have a systemd unit resolve protected disks at boot by serial / `by-id` into `/run/dfnix/protected.json`.
* [ ] **Append-Only Tamper-Evident Audit Logging:**
  - Record structured JSONL logs to both systemd journal and `/media/target/audit.jsonl`.
  - Log UTC timestamps, tool versions, exact command-line arguments, kernel versions, drive serials/WWNs, and pre/post read-only states.
  - Implement hash-chaining so log tampering is provably detectable in court.
* [ ] **Profile Modularization in `flake.nix`:**
  - Refactor duplicate `nixosConfigurations` into shared modular profiles (`profiles/base.nix`, `profiles/live.nix`, `profiles/appliance.nix`, `profiles/workstation.nix`).
  - Stamp `system.configurationRevision = self.rev or "dirty"` into all reports and CLI triage headers.
  - Pin releases to stable NixOS channels (`nixos-24.11`) rather than `nixos-unstable`.

---

## 5. Secure Boot Research & Architecture (`IDEAS.md`)

* **Firmware NVRAM Mutation Invariant:**
  - Disabling Secure Boot in firmware setup is an NVRAM modification.
  - Booting via `shim` writes `SbatLevel` to `EFI_VARIABLE_NON_VOLATILE`, and MOK key enrollment alters NVRAM state.
  - *Conclusion:* Neither method achieves true zero-touch firmware immutability. The requirement is documenting the specific modification performed in the chain of custody.
* **Kernel Lockdown Restrictions:**
  - Booting a signed kernel under Secure Boot enforces `lockdown=integrity`.
  - This blocks `/dev/mem` access, prohibits unsigned kernel modules, and prevents memory acquisition tools (e.g. LiME, custom hypervisor memory dumpers).
* **Strategic Recommendation:**
  - Maintain the native, pure NixOS Live ISO as the primary evidentiary acquisition platform.
  - Develop the signed `shim` / Secure Boot chainload as a separate, gated profile for specific client scenarios where firmware access is physically restricted.
