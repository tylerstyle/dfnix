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

# Determine root parent disk if a partition was passed
ROOT_DISK="$TARGET_DEV"
PKNAME=$(lsblk -no PKNAME "$TARGET_DEV" 2>/dev/null || true)
while [[ -n "$PKNAME" && -b "/dev/$PKNAME" ]]; do
    ROOT_DISK="/dev/$PKNAME"
    PKNAME=$(lsblk -no PKNAME "$ROOT_DISK" 2>/dev/null || true)
done

# Safety check 1: Prevent accidental overwrite of system drives
MOUNTED_SYSTEM=$(lsblk -no MOUNTPOINTS "$ROOT_DISK" 2>/dev/null | grep -E '^/(boot|nix|home|usr|etc|$)' || true)
if [ -n "$MOUNTED_SYSTEM" ]; then
    echo "[-] CRITICAL SAFETY REFUSAL: Device '$ROOT_DISK' hosts active system mount points:"
    echo "$MOUNTED_SYSTEM"
    echo "    Refusing to overwrite system media."
    exit 1
fi

# Safety check 2: Verify transport is removable USB unless --force
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

DEV_BASE="$(basename "$TARGET_DEV")"
echo -e "\033[1;31m[!] DANGER: ALL DATA ON $TARGET_DEV WILL BE PERMANENTLY ERASED!\033[0m"
read -rp "Type '${DEV_BASE}' to confirm and proceed with flashing: " CONFIRM
if [[ "$CONFIRM" != "$DEV_BASE" ]]; then
    echo "[-] Confirmation failed ('$CONFIRM' != '$DEV_BASE'). Flashing aborted."
    exit 1
fi

# Unmount any mounted partitions on target device
echo "[*] Ensuring all target partitions are unmounted..."
for part in $(lsblk -no PATH "$TARGET_DEV" | tail -n +2); do
    if mountpoint -q "$part" 2>/dev/null || grep -qs "^$part " /proc/mounts; then
        echo "    Unmounting $part..."
        sudo umount "$part" || { echo "[-] Failed to unmount $part"; exit 1; }
    fi
done

echo ""
echo "[*] Writing ISO to $TARGET_DEV (4M blocks, fsync)..."
sudo dd if="$ISO_FILE" of="$TARGET_DEV" bs=4M status=progress conv=fsync oflag=direct

echo "[*] Flushing kernel disk buffers..."
sudo sync

echo ""
echo "========================================================"
echo "[✓] SUCCESS: dfnix forensic ISO flashed to $TARGET_DEV"
echo "    You can now boot evidence systems with this drive."
echo "========================================================"
