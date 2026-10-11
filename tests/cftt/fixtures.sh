# Build the CFTT evidence disks inside the fixture builder VM. Every disk is left
# in the state a careless mount, assembly or resume would modify, and each state
# is asserted here so a fixture can never silently degrade into a clean one.
# The disks are addressed by the serial the test harness assigns them.

trap 'echo "fixture step failed (line $LINENO): $BASH_COMMAND" >&2' ERR

id=/dev/disk/by-id/virtio-
udevadm settle

mnt=$(mktemp -d)

content() { printf 'dfnix CFTT %s evidence\n' "$1"; }

# evidence.txt is written and checkpointed by a clean unmount. journal-only.txt is
# then committed to the journal/log, after which the disk "loses power": a dm-linear
# layer is switched to an error target, so no checkpoint, superblock update or
# unmount write ever reaches it. A mount that replays the log shows journal-only.txt,
# a mount without replay must not.
dirty_unmount() {
  local dev=$1 label=$2
  mount "$dev" "$mnt"
  content "$label" > "$mnt"/evidence.txt
  umount "$mnt"
  dmsetup create crashdisk --table "0 $(blockdev --getsz "$dev") linear $(readlink -f "$dev") 0"
  mount /dev/mapper/crashdisk "$mnt"
  # Persist the mounted state (ext4 needs_recovery) while nothing else is pending
  sync -f "$mnt"
  content "$label-journal-only" > "$mnt"/journal-only.txt
  # fsync commits the file to the journal (data first, delayed allocation resolved)
  sync "$mnt"/journal-only.txt
  # Cut the device without freezing the filesystem: a default suspend (lockfs)
  # freezes it, which syncs and checkpoints the journal first
  dmsetup suspend --nolockfs --noflush crashdisk
  dmsetup load crashdisk --table "0 $(blockdev --getsz "$dev") error"
  dmsetup resume crashdisk
  umount "$mnt" 2>/dev/null || umount -l "$mnt"
  dmsetup remove --retry crashdisk
  # The crash writes went through dm-0; drop the disk's own stale page cache
  blockdev --flushbufs "$dev"
}

# Prove the log really holds journal-only.txt by replaying it on a throwaway copy.
replay_on_copy() {
  local dev=$1 label=$2 copy loop
  copy=$(mktemp)
  dd if="$dev" of="$copy" bs=1M conv=sparse status=none
  loop=$(losetup -f --show "$copy")
  mount "$loop" "$mnt"
  grep -q "dfnix CFTT $label-journal-only evidence" "$mnt"/journal-only.txt
  umount "$mnt"
  losetup -d "$loop"
  rm "$copy"
}

echo "== ext4 with an unreplayed journal"
mkfs.ext4 -q -L EV-EXT4 "${id}EVID-EXT4"
dirty_unmount "${id}EVID-EXT4" ext4
dumpe2fs -h "${id}EVID-EXT4" 2>/dev/null | grep -q needs_recovery
replay_on_copy "${id}EVID-EXT4" ext4

echo "== XFS with a dirty log"
mkfs.xfs -q -L EV-XFS "${id}EVID-XFS"
dirty_unmount "${id}EVID-XFS" xfs
xfs_logprint -t "${id}EVID-XFS" 2>/dev/null | grep -q '<DIRTY>'
replay_on_copy "${id}EVID-XFS" xfs

echo "== NTFS with the volume dirty flag set"
# Neither ntfs3 nor ntfs-3g leaves the flag behind on demand, so write content with a
# clean mount, then set VOLUME_IS_DIRTY in $Volume's VOLUME_INFORMATION attribute as an
# unclean Windows shutdown would, in MFT record 3 and in its $MFTMirr copy.
mkntfs -q -F -Q -L EV-NTFS "${id}EVID-NTFS"
mount -t ntfs3 "${id}EVID-NTFS" "$mnt"
content ntfs > "$mnt"/evidence.txt
umount "$mnt"
python3 - "${id}EVID-NTFS" <<'PY'
import struct, sys

with open(sys.argv[1], "r+b") as dev:
    boot = dev.read(512)
    bps = struct.unpack_from("<H", boot, 0x0B)[0]
    cluster = bps * boot[0x0D]
    raw = struct.unpack_from("<b", boot, 0x40)[0]
    record = cluster * raw if raw > 0 else 1 << -raw
    for lcn_offset in (0x30, 0x38):  # $MFT, then $MFTMirr
        lcn = struct.unpack_from("<q", boot, lcn_offset)[0]
        pos = lcn * cluster + 3 * record
        dev.seek(pos)
        rec = bytearray(dev.read(record))
        assert rec[:4] == b"FILE", "MFT record 3 not found"
        usa_off, usa_cnt = struct.unpack_from("<HH", rec, 4)
        # Undo the update sequence fixups so attribute data reads correctly
        for i in range(1, usa_cnt):
            rec[i * bps - 2:i * bps] = rec[usa_off + 2 * i:usa_off + 2 * i + 2]
        off = struct.unpack_from("<H", rec, 0x14)[0]
        while True:
            atype, alen = struct.unpack_from("<II", rec, off)
            assert atype != 0xFFFFFFFF, "VOLUME_INFORMATION not found"
            if atype == 0x70:
                value = off + struct.unpack_from("<H", rec, off + 0x14)[0]
                flags = struct.unpack_from("<H", rec, value + 0x0A)[0]
                struct.pack_into("<H", rec, value + 0x0A, flags | 0x0001)
                break
            off += alen
        # Re-apply the fixups and write the record back
        usn = rec[usa_off:usa_off + 2]
        for i in range(1, usa_cnt):
            rec[usa_off + 2 * i:usa_off + 2 * i + 2] = rec[i * bps - 2:i * bps]
            rec[i * bps - 2:i * bps] = usn
        dev.seek(pos)
        dev.write(rec)
PY
sync
ntfsinfo -f -m "${id}EVID-NTFS" | grep 'Volume Flags' >&2
ntfsinfo -f -m "${id}EVID-NTFS" | grep 'Volume Flags' | grep -q DIRTY

echo "== LUKS2 container"
printf evidence | cryptsetup luksFormat --batch-mode --type luks2 \
  --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file - "${id}EVID-LUKS"
printf evidence | cryptsetup open --key-file - "${id}EVID-LUKS" evluks
mkfs.ext4 -q -L EV-LUKS-DATA /dev/mapper/evluks
mount /dev/mapper/evluks "$mnt"
content luks > "$mnt"/evidence.txt
umount "$mnt"
cryptsetup close evluks

echo "== RAID1 array across two disks"
mdadm --create /dev/md0 --name=evraid --run --assume-clean --level=1 --metadata=1.2 \
  --raid-devices=2 "${id}EVID-RAID-A" "${id}EVID-RAID-B"
mkfs.ext4 -q -L EV-RAID /dev/md0
mount /dev/md0 "$mnt"
content raid > "$mnt"/evidence.txt
umount "$mnt"
mdadm --stop /dev/md0

echo "== LVM volume group"
pvcreate -q "${id}EVID-LVM"
vgcreate -q evvg "${id}EVID-LVM"
lvcreate -q -y -l 100%FREE -n evlv evvg
mkfs.ext4 -q -L EV-LVM /dev/mapper/evvg-evlv
mount /dev/mapper/evvg-evlv "$mnt"
content lvm > "$mnt"/evidence.txt
umount "$mnt"
vgchange -q -an evvg

echo "== GPT disk: swap holding a hibernation image + data partition"
sgdisk -o -n1:0:+16M -t1:8200 -c1:swap -n2:0:0 -t2:8300 -c2:data "${id}EVID-HIBER" >/dev/null
udevadm settle
mkswap -q "${id}EVID-HIBER-part1"
# swsusp replaces SWAPSPACE2 at the end of the first page with its signature
printf 'S1SUSPEND\0' | dd of="${id}EVID-HIBER-part1" bs=1 seek=4086 conv=notrunc status=none
test "$(blkid -p -o value -s TYPE "${id}EVID-HIBER-part1")" = swsuspend
mkfs.ext4 -q -L EV-HIBER "${id}EVID-HIBER-part2"
mount "${id}EVID-HIBER-part2" "$mnt"
content hiber > "$mnt"/evidence.txt
umount "$mnt"

udevadm settle
sync
echo "== fixtures ready"
