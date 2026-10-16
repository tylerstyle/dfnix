# Live Acquisition Checklist: Running Linux System

Use this checklist when a Linux workstation, server, NAS, or appliance is found
running at the scene. Mount `KIT-LNX` (`ext4`, GPT read-only bit 60 set, tool
files marked `chattr +i`) read-only at `/mnt/kit`, mount an external USB target
drive at `/mnt/target` (for memory dumps, volume images, and UAC archives), and
mount `KIT-OUT` (`exfat`) at `/mnt/out`:

```sh
mkdir -p /mnt/kit /mnt/target /mnt/out
mount -o ro,noload /dev/disk/by-label/KIT-LNX /mnt/kit
mount /dev/sdY1 /mnt/target                     # external target drive
mount /dev/disk/by-label/KIT-OUT /mnt/out       # requires kernel exFAT (Linux >= 5.7)
mkdir -p /mnt/out/case
```

*(On Linux kernels older than 5.7 without `exfat` support, skip mounting
`KIT-OUT` and write `/mnt/out/case` outputs to `/mnt/target/case` or stream
them to `dfnix`.)*

Put the kit's static musl tools (`/mnt/kit/uac/bin/linux/x86_64` or `aarch64`)
first in `PATH` so you do not rely on potentially trojaned system binaries:

```sh
ARCH=$(uname -m)   # x86_64 or aarch64
export PATH="/mnt/kit/uac/bin/linux/$ARCH:$PATH"
```

> **Footprint & Warnings**
> - **Desktop automounters:** `udisks2` on desktop Linux may auto-mount
>   partitions read-write when the stick is plugged in. Remount `KIT-LNX`
>   read-only (`mount -o remount,ro /dev/disk/by-label/KIT-LNX`) immediately;
>   every file on `KIT-LNX` also carries the `ext4` immutable attribute (`+i`).
> - **Kernel keyring & LUKS2:** Pulling the power on a LUKS-encrypted server or
>   laptop destroys the volume master key in RAM. Capture keys (Step 2), RAM
>   (Step 3), and the unlocked `/dev/mapper/*` device (Step 5) before power-off.

---

## 1. Record the scene

1. **Photograph the console/screen** (active terminals, desktop session, LEDs).
2. **Keep the session awake:**
   ```sh
   systemd-inhibit --what=idle:sleep:handle-lid-switch sleep 86400 &
   setterm -blank 0 -powerdown 0 2>/dev/null || true
   ```
3. **Record reference time vs. system clock** (compare against the examiner's
   reference UTC clock):
   ```sh
   { date -u +"suspect_utc:   %Y-%m-%dT%H:%M:%SZ"
     date    +"suspect_local: %Y-%m-%dT%H:%M:%S%z"
     cat /proc/uptime
     timedatectl status 2>/dev/null || true
   } > /mnt/out/case/01-clock.txt
   ```

## 2. Encryption state and key material (seconds — before memory on purpose)

Run **before** memory capture: it takes seconds and needs no driver, whereas heavy
I/O can hang an unstable system. Note this deliberate deviation from strict order
of volatility in the report.

```sh
{ lsblk -f -o NAME,FSTYPE,LABEL,UUID,FSAVAIL,FSUSE%,MOUNTPOINTS
  echo "=== dmsetup table --showkeys ==="
  dmsetup table --showkeys
  echo "=== cryptsetup status ==="
  for m in /dev/mapper/*; do
    [ "$m" = "/dev/mapper/control" ] && continue
    echo "--- $m ---"
    cryptsetup status "$m" 2>&1 || true
  done
  echo "=== ZFS encryption ==="
  zpool status 2>/dev/null || true
  zfs get -r encryption,keystatus,keylocation 2>/dev/null || true
  echo "=== /etc/crypttab ==="
  cat /etc/crypttab 2>/dev/null || true
} > /mnt/out/case/02-encryption-keys.txt
```

- **Key material handling:** `chmod` has no effect on `KIT-OUT` (exFAT), and
  `02-encryption-keys.txt` may contain raw volume master keys. Treat the stick
  as sensitive key material (store in a sealed evidence bag after the scene)
  until `dflive keys` encrypts it with `age`.
- **LUKS1 / plain dm-crypt:** `dmsetup table --showkeys` prints the hex volume
  master key directly in column 5. (`dfmount unlock` does not take a raw volume
  key yet; on `dfnix`, unlock the offline disk image directly with `cryptsetup`:
  `xxd -r -p key.hex > key.bin && cryptsetup open --readonly --type luks --volume-key-file key.bin /dev/loop0pX ev_luks`,
  or `--type plain` with the cipher and sector size from `dmsetup table`.)
- **LUKS2 kernel keyring warning:** LUKS2 stores the volume key in the kernel
  keyring by default, so `dmsetup table --showkeys` shows a reference such as
  `:64:logon:cryptsetup:xxxx` instead of the raw hex key (`logon` keys cannot be
  read back from userland via `keyctl pipe`). When you see `:logon:cryptsetup:`:
  1. The master key resides in kernel memory — **Step 3 (AVML memory dump) is
     mandatory** so `findaes` / Volatility can recover it.
  2. **Step 5 (live streaming of `/dev/mapper/<name>`) is mandatory** to guarantee
     access to the plaintext volume without cracking the passphrase.
- Back up every LUKS header (`cryptsetup luksHeaderBackup /dev/sdXN --header-backup-file /mnt/out/case/luks-sdXN.hdr`).

## 3. Memory (static AVML)

`KIT-LNX` includes static musl `avml` (`x86_64` and `aarch64`), which acquires
physical RAM via `/dev/crash`, `/proc/kcore`, or `/dev/mem` without compiling or
loading a kernel module. Write the dump to `/mnt/target` and record the smear window:

```sh
date -u +"start_utc: %Y-%m-%dT%H:%M:%SZ" > /mnt/out/case/03-mem-window.txt
/mnt/kit/avml/$ARCH/avml acquire --compress /mnt/target/physmem_$(hostname).lime
date -u +"end_utc:   %Y-%m-%dT%H:%M:%SZ" >> /mnt/out/case/03-mem-window.txt
sha256sum /mnt/target/physmem_$(hostname).lime > /mnt/out/case/03-mem.sha256
```

- **Kernel symbols for Volatility 3:** copy the running kernel's BTF and symbol
  files so `dwarf2json` / Volatility 3 on `dfnix` can build an ISF profile:
  ```sh
  cp -p /sys/kernel/btf/vmlinux /mnt/out/case/vmlinux.btf 2>/dev/null || true
  cp -p "/boot/System.map-$(uname -r)" "/boot/config-$(uname -r)" "/boot/vmlinuz-$(uname -r)" /mnt/out/case/ 2>/dev/null || true
  ```
- *Footprint:* single static userland process reading `/proc/kcore` or `/dev/crash`;
  no kernel module (`insmod`) is loaded.

## 4. Volatile state (using static `KIT-LNX` binaries)

With `/mnt/kit/uac/bin/linux/$ARCH` first in `PATH`, `ss`, `ip`, `arp`, `netstat`,
`ps`, `lsof`, `find`, and `sha256sum` execute the kit's static musl binaries:

```sh
{ ss -tulpan; echo "---"; netstat -tulpan; } > /mnt/out/case/04-sockets.txt 2>&1
{ ip addr; echo "---"; ip route show table all; echo "---"; ip neigh; } > /mnt/out/case/04-network.txt
ps auxwwf > /mnt/out/case/04-pstree.txt
lsof -n -P -l > /mnt/out/case/04-lsof.txt 2>&1
sha256sum /proc/[0-9]*/exe > /mnt/out/case/04-exe-hashes.txt 2>/dev/null || true
{ who -a; echo "---"; w; echo "---"; last -F -n 50; } > /mnt/out/case/04-users.txt 2>&1
cat /proc/mounts > /mnt/out/case/04-mounts.txt
crontab -l > /mnt/out/case/04-cron-root.txt 2>&1 || true
ls -la /etc/cron* /var/spool/cron /var/spool/cron/crontabs /etc/systemd/system > /mnt/out/case/04-scheduled.txt 2>&1
```

## 5. Unlocked volumes, live

For every unlocked `/dev/mapper/<name>`, unlocked ZFS dataset, or active software
RAID/LVM volume whose key could not be extracted in hex in Step 2:

- **Authenticated stream to `dfnix` (`dfnet stream` + `dflive send`, once `dflive` is on the kit):**
  ```sh
  # On dfnix:
  dfnet stream --bind 10.0.0.1 -o /media/target/case01/live -C "CASE" -E live01 -e "Examiner"
  # On the Linux suspect (using the 10-digit pairing code shown by dfnet):
  dflive send /dev/mapper/<name> --to 10.0.0.1:9998 --code "123 456 7890" --log /mnt/out/case/05-dflive.jsonl
  ```
- **Local fallback to `/mnt/target` (until `dflive` is on the kit):**
  ```sh
  dd if=/dev/mapper/<name> of=/mnt/target/<name>.raw bs=4M status=progress conv=noerror,sync
  sha256sum /mnt/target/<name>.raw > /mnt/out/case/05-<name>.sha256
  ```
- **Encrypted ZFS datasets:** prefer imaging unlocked zvols (`/dev/zvol/...`) or
  collecting mounted datasets logically. (`zfs send -R` requires creating a
  snapshot, which writes to the suspect's pool — use it only as a documented
  modification after an explicit decision.)

## 6. Artifacts (`uac-kit` or Velociraptor Linux)

Run `uac-kit` **from its own directory on `KIT-LNX`** (upstream `uac` requires
the current working directory to be its root; uses its bundled static GNU
`coreutils` with `statx(2)` birth-time support, `findutils`, `procps`, `lsof`,
`iproute2`, `net-tools`, and `busybox`):

```sh
(cd /mnt/kit/uac && ./uac -p ir_triage /mnt/target/)
```

- Use `-p full` when time and target space allow full artifact + bodyfile
  collection.
- Alternatively, `KIT-LNX` also provides `/mnt/kit/velociraptor/velociraptor-linux-amd64`
  (and `arm64`) for VQL-based collection.
- *Footprint:* creates a temporary staging directory inside `/mnt/target/` and
  reads `/proc`, `/sys`, `/etc`, and `/var/log`.

## 7. Remote footprint on the device

Record cloud credentials, active SSH control sockets/agents, mail spools,
containers, and Kerberos tickets for the **§ 110 Abs. 3 StPO** decision:

```sh
klist > /mnt/out/case/07-kerberos.txt 2>&1 || true
find /root /home -maxdepth 3 \( \
  -name ".aws" -o -name ".azure" -o -name ".config" -o -name ".kube" \
  -o -name ".ssh" -o -name ".gnupg" -o -name ".docker" -o -name ".rclone*" \
  \) -ls > /mnt/out/case/07-remote-footprint.txt 2>/dev/null
ls -la /tmp/ssh-* /run/user/*/keyring* /run/user/*/gnupg* >> /mnt/out/case/07-remote-footprint.txt 2>/dev/null || true
```

- **Do NOT use captured SSH agents, cloud tokens, or kubeconfigs to access remote
  systems** without explicit legal authorization; doing so alters remote access
  logs and may alert monitoring systems.

## 8. Shut down or pull the plug, and image with `dfdisk`

1. **STOP — Gate before power-off:** Confirm that for **every** encrypted volume
   (LUKS1/2, plain dm-crypt, ZFS, etc.) you have either (a) the verified hex
   master key / passphrase from Step 2, or (b) a completed, hash-verified live
   image of `/dev/mapper/<name>` from Step 5. Pulling the plug on a LUKS2 volume
   whose key is only in the kernel keyring without a live image locks the volume.
2. Unmount the target and kit partitions cleanly:
   ```sh
   sync
   umount /mnt/target /mnt/out /mnt/kit
   ```
3. Pull the plug (or run `poweroff -f` / graceful shutdown if enterprise RAID or
   policy requires it), boot `dfnix` (or connect disks via write-blocker), and
   image all physical disks with `dfdisk`.
4. On `dfnix`, verify the field-kit stick against `KIT-MANIFEST.sha256` to confirm
   no tool file was altered.
