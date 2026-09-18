#!/usr/bin/env bash
# ==============================================================================
# dfnix USB Flashing Utility
# Safely writes the built dfnix live forensic ISO onto target USB storage
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_FILE="${SCRIPT_DIR}/result-iso/iso/dfnix-forensics.iso"
TARGET_DEV="${1:-/dev/sda}"

echo "========================================================"
echo "          dfnix Forensic ISO Flash Tool                "
echo "========================================================"

if [ ! -f "$ISO_FILE" ]; then
    echo "[-] Error: ISO image not found at: $ISO_FILE"
    echo "    Please run 'make iso' first."
    exit 1
fi

if [ ! -b "$TARGET_DEV" ]; then
    echo "[-] Error: Target device '$TARGET_DEV' is not a valid block device!"
    exit 1
fi

# Safety check: Prevent accidental overwrite of system drives
MOUNTED_SYSTEM=$(lsblk -no MOUNTPOINTS "$TARGET_DEV" | grep -E '^/(boot|nix|home|$)' || true)
if [ -n "$MOUNTED_SYSTEM" ]; then
    echo "[-] CRITICAL SAFETY REFUSAL: Device '$TARGET_DEV' hosts active system mount points:"
    echo "$MOUNTED_SYSTEM"
    echo "    Refusing to overwrite system media."
    exit 1
fi

echo "[+] Source ISO : $ISO_FILE ($(du -h "$ISO_FILE" | cut -f1))"
echo "[+] Target Drive:"
lsblk -o NAME,SIZE,TYPE,VENDOR,MODEL,TRAN,MOUNTPOINTS "$TARGET_DEV"
echo ""

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
