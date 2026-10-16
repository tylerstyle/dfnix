# Reassembling RAID, LVM and ZFS read-only

dfmount refuses RAID members, LVM physical volumes and ZFS pool devices. Never
assemble them on the original disks: md resyncs and updates event counters, LVM
can rewrite metadata, and a read-write ZFS import writes to every label. Image
the members first, then put the volume back together from the images, with
every layer read-only.

The CFTT test (`make test-cftt`) runs the md, LVM and ZFS steps below against
evidence disks and checks that every disk is bit-identical afterwards.

## 1. Image every member

- Image each member disk with dfdisk, as for any other disk.
- Record serial, model and position: bay or slot number, controller port,
  enclosure. Photograph the bays before removing any disk.
- Note the controller (onboard SATA, HBA, hardware RAID, NAS model). With
  hardware RAID, image the logical volume the controller presents as well
  (boot dfnix on the server).

## 2. Attach the images read-only

`losetup -r` opens the image file read-only, so nothing that sits on top of the
loop device can write to it.

```sh
losetup -r -f --show /media/target/case/disk1.raw     # prints /dev/loop0
losetup -r -f --show /media/target/case/disk2.raw     # prints /dev/loop1
```

- **E01 images:** expose the raw stream first, then loop that:
  `ewfmount /media/target/case/disk1.E01 /mnt/ewf1` and
  `losetup -r -f --show /mnt/ewf1/ewf1`.
- **ZFS** puts its pool on partition 1 when it was given a whole disk. Add `-P`
  so the loop device gets partitions: `losetup -r -P -f --show disk3.raw`, then
  use `/dev/loop2p1`.
- Check each loop device: `blockdev --getro /dev/loop0` must print `1`.

## 3. Assemble

### md (Linux software RAID, Synology SHR, many NAS)

```sh
mdadm --examine /dev/loop0 /dev/loop1                 # level, UUID, member order
mdadm --assemble --readonly /dev/md100 /dev/loop0 /dev/loop1
cat /sys/block/md100/md/array_state                    # readonly
```

Name the array by a free device number such as `/dev/md100`. dfnix leaves out
mdadm's udev rules (they would assemble arrays on their own), so no
`/dev/md/<name>` links appear.

Synology SHR and QNAP use several md arrays (one per partition set) with LVM on
top: assemble each array, then continue with LVM on the md devices.

Not yet covered by the CFTT test: Intel RST (IMSM) and SNIA DDF containers, which
mdadm also reads; degraded arrays; QNAP's LVM thin pools
(thin-provisioning-tools is installed).

### LVM

`--devices` limits LVM to the loop devices: the original disk, if attached,
carries the same physical volume. `metadata_read_only` stops any metadata
write, and `read_only_volume_list` activates the logical volumes read-only.

```sh
pvs --devices /dev/loop0                               # shows the volume group
vgchange -ay --devices /dev/loop0 \
  --config 'global { metadata_read_only = 1 } activation { read_only_volume_list = [ "VG" ] }' VG
blockdev --getro /dev/VG/LV                            # 1
```

A volume group on several images takes them as a list:
`--devices /dev/loop0,/dev/loop1`.

### ZFS

```sh
zpool import -d /dev/loop2p1                           # lists the pool and its state
zpool import -o readonly=on -o cachefile=none -N -R /mnt/zfs -d /dev/loop2p1 -f POOL
zpool get readonly POOL                                # on
zfs mount POOL                                         # mounts below /mnt/zfs
```

- A pool on several images takes one `-d` per device:
  `-d /dev/loop2p1 -d /dev/loop3p1`.
- `-f` is needed when the pool was never exported, which is normal for a seized
  system. With `readonly=on` it changes nothing on the images.
- `cachefile=none` keeps the pool out of `/etc/zfs/zpool.cache`; `-N` mounts
  nothing until you ask; `-R` keeps every mount point below `/mnt/zfs`.
- Encrypted datasets: `zfs load-key POOL/DATASET` with the key or passphrase.

## 4. Mount the filesystems

Mount the assembled device read-only without journal replay, for example
`mount -o ro,noload /dev/md100 /mnt/md` for ext4, or image the assembled
device with dfdisk to get one image of the whole volume.

## 5. Take it apart again

```sh
umount /mnt/md
mdadm --stop /dev/md100
vgchange -an --devices /dev/loop0 --config 'global { metadata_read_only = 1 }' VG
zpool export POOL
losetup -d /dev/loop0 /dev/loop1 /dev/loop2
```

Then verify the member images against their reports with `dfdisk verify`.
