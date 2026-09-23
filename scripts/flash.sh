#!/usr/bin/env bash
# ==============================================================================
# dfnix USB Flashing Utility
# Safely writes the built dfnix live forensic ISO onto target USB storage
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_FILE="${SCRIPT_DIR}/result-iso/iso/dfnix-forensics.iso"
TARGET_DEV="${1:-}"
ALLOW_INTERNAL="${2:-}"

echo "========================================================"
echo "          dfnix Forensic ISO Flash Tool                "
echo "========================================================"

if [ -z "$TARGET_DEV" ]; then
    echo "[-] Error: No target device specified!"
    echo "    Usage: $0 /dev/sdX [--force]"
    echo ""
    echo "[*] Detected removable/USB block devices:"
    lsblk -d -o NAME,SIZE,TYPE,VENDOR,MODEL,TRAN,RM 2>/dev/null || true
    exit 1
fi

if [ ! -f "$ISO_FILE" ]; then
    echo "[-] Error: ISO image not found at: $ISO_FILE"
    echo "    Please run 'make iso' first."
    exit 1
fi

if [ ! -b "$TARGET_DEV" ]; then
    echo "[-] Error: Target device '$TARGET_DEV' is not a valid block device!"
    exit 1
fi

# Forensic Invariant: Target must be a whole disk, not an individual partition
DEV_TYPE=$(lsblk -dno TYPE "$TARGET_DEV" 2>/dev/null || true)
if [[ "$DEV_TYPE" != "disk" ]]; then
    echo "[-] CRITICAL ERROR: Target device '$TARGET_DEV' is a $DEV_TYPE, not a whole disk!"
    echo "    Flashing a hybrid bootable ISO requires writing to the complete physical disk."
    PKNAME=$(lsblk -no PKNAME "$TARGET_DEV" 2>/dev/null || true)
    while [[ -n "$PKNAME" && -b "/dev/$PKNAME" ]]; do
        CANDIDATE="/dev/$PKNAME"
        PKNAME=$(lsblk -no PKNAME "$CANDIDATE" 2>/dev/null || true)
    done
    if [[ -n "${CANDIDATE:-}" && -b "$CANDIDATE" ]]; then
        echo "    Did you mean parent disk: $CANDIDATE ?"
    fi
    exit 1
fi

ROOT_DISK="$TARGET_DEV"

# Safety check 1: Prevent accidental overwrite of system & live boot drives
# Check root, /iso, /sysroot, /boot, /nix, etc. across the target and all its partitions
MOUNTED_SYSTEM=$(lsblk -no MOUNTPOINTS "$ROOT_DISK" 2>/dev/null | grep -E '^/(iso|sysroot|boot|nix|home|usr|etc|var|$)' || true)
if [ -n "$MOUNTED_SYSTEM" ]; then
    echo "[-] CRITICAL SAFETY REFUSAL: Device '$ROOT_DISK' hosts active system mount points:"
    echo "$MOUNTED_SYSTEM"
    echo "    Refusing to overwrite system media."
    exit 1
fi

# Safety check 2: Refuse devices containing protected live OS or boot filesystem labels
LIVE_LABEL=$(lsblk -no LABEL "$ROOT_DISK" 2>/dev/null | grep -E '^(DFNIX_LIVE|NIXOS_.*|BOOT|ESP)$' || true)
if [ -n "$LIVE_LABEL" ]; then
    echo "[-] CRITICAL SAFETY REFUSAL: Device '$ROOT_DISK' hosts protected live/boot volume labels:"
    echo "$LIVE_LABEL"
    echo "    Refusing to overwrite active live boot or OS media."
    exit 1
fi

# Safety check 3: Verify transport is removable USB unless --force
IS_USB=$(lsblk -d -no TRAN "$ROOT_DISK" 2>/dev/null || true)
IS_RM=$(lsblk -d -no RM "$ROOT_DISK" 2>/dev/null || true)
if [[ "$IS_USB" != "usb" && "$IS_RM" != "1" && "$ALLOW_INTERNAL" != "--force" ]]; then
    echo "[-] SAFETY REFUSAL: '$ROOT_DISK' does not appear to be a removable USB drive (TRAN=${IS_USB:-none}, RM=${IS_RM:-0})."
    echo "    To override on internal/fixed media, pass --force as the second argument."
    exit 1
fi

echo "[+] Source ISO : $ISO_FILE ($(du -h "$ISO_FILE" | cut -f1))"
echo "[+] Target Drive:"
lsblk -o NAME,SIZE,TYPE,VENDOR,MODEL,TRAN,MOUNTPOINTS "$ROOT_DISK"
echo ""

DEV_BASE="$(basename "$ROOT_DISK")"
echo -e "\033[1;31m[!] DANGER: ALL DATA ON $ROOT_DISK WILL BE PERMANENTLY ERASED!\033[0m"
read -rp "Type '${DEV_BASE}' to confirm and proceed with flashing: " CONFIRM
if [[ "$CONFIRM" != "$DEV_BASE" ]]; then
    echo "[-] Confirmation failed ('$CONFIRM' != '$DEV_BASE'). Flashing aborted."
    exit 1
fi

# Unmount all mounted nodes (partitions and the whole disk itself) in reverse topological order
echo "[*] Ensuring all target disk partitions and mounts are unmounted..."
mapfile -t ALL_NODES < <(lsblk -no PATH "$ROOT_DISK" 2>/dev/null | tac)
for node in "${ALL_NODES[@]}"; do
    if [[ -n "$node" && -b "$node" ]]; then
        if mountpoint -q "$node" 2>/dev/null || grep -qs "^$node " /proc/mounts; then
            echo "    Unmounting active mount on $node..."
            sudo umount "$node" || { echo "[-] Failed to unmount $node"; exit 1; }
        fi
    fi
done

echo ""
echo "[*] Writing ISO to $ROOT_DISK (4M blocks, fsync)..."
sudo dd if="$ISO_FILE" of="$ROOT_DISK" bs=4M status=progress conv=fsync oflag=direct

echo "[*] Flushing kernel disk buffers..."
sudo sync

echo ""
echo "========================================================"
echo "[✓] SUCCESS: dfnix forensic ISO flashed to $ROOT_DISK"
echo "    You can now boot evidence systems with this drive."
echo "========================================================"
