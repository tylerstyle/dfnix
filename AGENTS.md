# AI Agent & Pair Programming Guidelines for `dfnix`

This document contains critical architectural context, repository boundaries, and developer instructions for AI assistants (Google Antigravity, Claude Code, Cursor, SWE-agent, etc.) working on `dfnix`.

---

## ⚠️ CRITICAL: Multi-Repository Architecture

**`dfnix` is NOT a monorepo for the forensic tools.**

`dfnix` is the **NixOS distribution configuration and integration layer** (`tylerstyle/dfnix`). The core forensic tools packaged into `dfnix` are maintained as **separate, independent Git projects** under `~/git/`:

| Repository | Path | Upstream Remote | Technology | Description |
| :--- | :--- | :--- | :--- | :--- |
| **`dfdisk`** | `~/git/dfdisk` | `git@github.com:tylerstyle/dfdisk.git` | Rust (ratatui / clap) | Forensic disk imaging, damaged media rescue (.E01 / raw), and hash verification. |
| **`dfmount`** | `~/git/dfmount` | `git@github.com:tylerstyle/dfmount.git` | Rust (ratatui) + Python/Bash | Forensic storage mounter (zero journal replay) & target unblocker. |
| **`dfnet`** | `~/git/dfnet` | `git@github.com:tylerstyle/dfnet.git` | Rust (ratatui / clap) + Bash | Network triage, MAC spoofing, Wi-Fi hotspot AP, share ingest, and raw streams. |
| **`df-datenbank`** | `~/git/df-datenbank` | `git@github.com:tylerstyle/df-datenbank.git` | Database / Web | Forensic case & evidence tracking database. |
| **`dfnix`** | `~/git/dfnix` | `git@github.com:tylerstyle/dfnix.git` | Nix / Bash | Live bootable NixOS ISO, hardware write-blocking, desktop configs (Niri/XFCE). |

---

## 🚨 Golden Rules for AI Agents

### 1. Never modify a tool only inside `dfnix/pkgs/`
If a user requests changes, bug fixes, or new features in **`dfnet`**, **`dfmount`**, or **`dfdisk`**:
- **First, locate the tool's standalone repository** at `~/git/<tool>` (e.g. `/home/df/git/dfnet`).
- **Implement and verify the change in the tool's repository** (`src/main.rs`, `Cargo.toml`, `scripts/`, etc.).
- **Verify compilation and tests** in that repository (`cargo check`, `cargo test`).
- **Sync companion scripts or derivations** in `dfnix/pkgs/<tool>/` if `dfnix` vendors or packages matching scripts (e.g., `pkgs/dfnet/dfnet.sh`, `pkgs/dfmount/dfmount.sh`).

### 2. Know where each tool is integrated in `dfnix`
- **`dfdisk`**:
  - Pinned in `flake.nix` (`inputs.dfdisk.url = "github:tylerstyle/dfdisk"`) and packaged via `pkgs/dfdisk/default.nix` using `fetchFromGitHub`.
- **`dfmount`**:
  - Packaged via `pkgs/dfmount/default.nix`.
  - Companion scripts in `pkgs/dfmount/` (`dfmount.sh`, `dfmount-tui.py`, `dfmount-gui.py`) mirror upstream `~/git/dfmount/scripts/`.
- **`dfnet`**:
  - Packaged via `pkgs/dfnet/default.nix`.
  - Standalone Rust binary at `~/git/dfnet`, companion script at `~/git/dfnet/scripts/dfnet.sh` mirrored in `dfnix/pkgs/dfnet/dfnet.sh`.
- **`dfinfo`**:
  - Local to `dfnix/pkgs/dfinfo/` (does not have an independent external repository).

### 3. Forensic Safety Invariants (Do Not Break!)
- **Hardware Write Blocking**:
  - Kernel parameters (`systemd.gpt_auto=0`, `systemd.targets.swap.enable=false`) and udev rules in `modules/hardware/write-blocking.nix` must keep evidence block devices write-blocked by default.
  - Device matching must match parent block devices and their partitions (`sd[a-z]*`, `nvme[0-9]*n[0-9]*`, `mmcblk[0-9]*`).
- **System Device Protection**:
  - Live ISO mountpoints (`/iso`, `/sysroot`), root (`/`), `/boot`, `/nix`, and media labeled `DFNIX_LIVE` must never be unblocked or selected as target drives.
  - If a device or any of its partitions contain a system mount, all child partitions must inherit system status (`parent_is_sys`).

---

## 🧪 Verification Commands

Always run the following commands before completing tasks:

### In `dfnix` (`/home/df/git/dfnix`):
```bash
# Comprehensive flake check, shellcheck, and flakeless instantiation
make check

# Or individual checks:
nix flake check --no-build
shellcheck pkgs/*/*.sh modules/*/*.sh scripts/*.sh
```

### In Rust Tools (`dfdisk`, `dfmount`, `dfnet`):
```bash
cargo check --manifest-path /home/df/git/<tool>/Cargo.toml
cargo test --manifest-path /home/df/git/<tool>/Cargo.toml
```
