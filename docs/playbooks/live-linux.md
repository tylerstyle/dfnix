# Live Acquisition Checklist: Running Linux System

Use this checklist when a Linux workstation, server, NAS, or appliance is found
running at the scene. Mount `KIT-LNX` (`ext4`, GPT read-only bit 60 set, tool
files marked `chattr +i`) read-only at `/mnt/kit`, mount an external USB target
drive at `/mnt/target` (for memory dumps, local volume images, and UAC archives),
and mount `KIT-OUT` (`exfat`) at `/mnt/out`:

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

Put the kit's static musl `dflive` (`/mnt/kit/dflive/$ARCH/dflive`) and static
userland tools (`/mnt/kit/uac/bin/linux/$ARCH`) first in `PATH` so you do not
rely on potentially trojaned system binaries:

```sh
ARCH=$(uname -m)   # x86_64 or aarch64
export PATH="/mnt/kit/dflive/$ARCH:/mnt/kit/uac/bin/linux/$ARCH:$PATH"
```

Pass `--log /mnt/out/case/dflive.jsonl` on every `dflive` command: each run
appends one JSON line recording `dflive`'s own SHA-256, whether
`/mnt/kit/KIT-MANIFEST.sha256` lists it with that hash, every child command and
exit status, every file written with its SHA-256, and the outcome.

> **Footprint & Warnings**
> - **Desktop automounters:** `udisks2` on desktop Linux may auto-mount
>   partitions read-write when the stick is plugged in. Remount `KIT-LNX`
>   read-only (`mount -o remount,ro /dev/disk/by-label/KIT-LNX`) immediately;
>   every file on `KIT-LNX` also carries the `ext4` immutable attribute (`+i`).
> - **Kernel keyring & LUKS2:** Pulling the power on a LUKS-encrypted server or
>   laptop destroys the volume master key in RAM. Capture keys (Step 2), RAM
>   (Step 3), and the unlocked `/dev/mapper/*` device (Step 5) before power-off.

---

## 1. Record the scene (`dflive status`)

1. **Photograph the console/screen** (active terminals, desktop session, LEDs).
2. **Keep the session awake:**
   ```sh
   systemd-inhibit --what=idle:sleep:handle-lid-switch sleep 86400 &
   setterm -blank 0 -powerdown 0 2>/dev/null || true
   ```
3. **Record the scene and clock offset** against a trusted reference clock
   (radio clock, phone) typed as RFC 3339 with offset:
   ```sh
   dflive status --reference-time 2026-10-16T17:05:00+02:00 \
     -o /mnt/out/case/01-status.json --log /mnt/out/case/dflive.jsonl
   ```
   `01-status.json` records the system clock and its offset in seconds against
   `--reference-time`, OS and kernel release, time zone, boot time, logged-in
   users, whether `dflive` runs as root, disks and partitions (model, serial,
   size, mounts, holders, LUKS header presence), open `dm-crypt` mappings at a
   glance, and running cloud sync clients (`Dropbox`, `Nextcloud`, `Syncthing`,
   `rclone`, `insync`, etc.) with their folders (looked up by known names in
   each login profile without listing home directories).

## 2. Encryption state and key material (`dflive keys` — before memory on purpose)

Run **before** memory capture: it takes seconds and needs no driver, whereas heavy
I/O can hang an unstable system. Note this deliberate deviation from strict order
of volatility in the report.

```sh
dflive keys -o /mnt/out/case/02-keys.json.age --recipient age1... \
  --log /mnt/out/case/dflive.jsonl
```

- `dflive keys` copies every LUKS header area raw from block devices (LUKS1 up to
  the payload offset, LUKS2 up to the first data segment, base64-encoded under
  `details.luks_headers` so each works directly as a detached `--header` backup),
  records `dmsetup table --showkeys` (hex volume master keys for LUKS1 and plain
  `dm-crypt`, or keyring references for LUKS2), active `dm` mappings with backing
  devices, ZFS encryption properties (`zfs get`), and `/etc/crypttab`.
- The document is encrypted to the examiner's `age` X25519 public key
  (`--recipient`, repeatable) before it is written, so master keys never lie in
  plain text on `KIT-OUT` (exFAT). If no examiner `age` public key is at hand,
  pass `--plaintext` (`-o /mnt/out/case/02-keys.json --plaintext`) and store the
  stick in a sealed evidence bag after the scene.
- **LUKS1 / plain dm-crypt:** after decrypting (`age -d -i examiner.key
  02-keys.json.age`), `details.commands[0].stdout` (`dmsetup table --showkeys`)
  holds the hex volume master key in column 5. On `dfnix`, unlock the offline
  disk image read-only with `cryptsetup`:
  `xxd -r -p key.hex > key.bin && cryptsetup open --readonly --type luks --volume-key-file key.bin /dev/loop0pX ev_luks`
  (or `--type plain` with the cipher and sector size from `dmsetup table`).
- **LUKS2 kernel keyring warning (`details.keyring_keys: true`):** LUKS2 stores
  the volume key in the kernel keyring by default (`:64:logon:cryptsetup:xxxx`),
  which cannot be read back from user space via `keyctl pipe`. When `keyring_keys`
  is `true`:
  1. The master key resides in kernel memory — **Step 3 (`dflive mem` memory
     dump) is mandatory** so `findaes` / Volatility can recover it.
  2. **Step 5 (live streaming of `/dev/mapper/<name>`) is mandatory** to guarantee
     access to the plaintext volume without cracking the passphrase.

## 3. Memory (`dflive mem` with static AVML)

`dflive mem` automatically locates `/mnt/kit/avml/$ARCH/avml` on `KIT-LNX`,
acquires physical RAM via `/dev/crash`, `/proc/kcore`, or `/dev/mem` without
compiling or loading a kernel module, hashes the dump, and writes
`/mnt/target/physmem_$(hostname).lime.json` next to it with `avml`'s SHA-256,
the capture window (`started` to `finished`), exit code, and the dump's size and
SHA-256:

```sh
dflive mem -o "/mnt/target/physmem_$(hostname).lime" --compress \
  --log /mnt/out/case/dflive.jsonl
```

- **Kernel symbols for Volatility 3:** copy the running kernel's BTF and symbol
  files so `dwarf2json` / Volatility 3 on `dfnix` can build an ISF profile:
  ```sh
  cp -p /sys/kernel/btf/vmlinux /mnt/out/case/vmlinux.btf 2>/dev/null || true
  cp -p "/boot/System.map-$(uname -r)" "/boot/config-$(uname -r)" "/boot/vmlinuz-$(uname -r)" /mnt/out/case/ 2>/dev/null || true
  ```
- *Footprint:* single static userland process reading `/proc/kcore` or `/dev/crash`;
  no kernel module (`insmod`) is loaded.

## 4. Volatile state (`dflive state`)

`dflive state` reads the volatile state with its own code directly from `/proc`,
`/sys`, `utmp`, and `getifaddrs` rather than spawning the suspect's possibly
trojaned `ps`, `netstat`, or `who`:

```sh
dflive state -o /mnt/out/case/04-state.json --log /mnt/out/case/dflive.jsonl
```

`04-state.json` records:
- processes with PID, PPID, state, start time, UID, command line, `/proc/<pid>/exe`
  target, and executable SHA-256 opened with `O_NOATIME` so access times are not
  updated (`--no-hash` skips hashing executables);
- TCP and UDP sockets (IPv4 and IPv6) with owning PIDs and inodes;
- network interfaces and addresses, routing tables, ARP cache, and DNS
  configuration (`/etc/resolv.conf`);
- mounts (`/proc/mounts`), swap, loaded kernel modules (`/proc/modules`), and
  logged-in users (`utmp`).

Supplement with open files and deleted files still held open (such as unlinked
binaries or deleted logs) using the kit's static `lsof` (first in `PATH`):

```sh
lsof -n -P -l > /mnt/out/case/04-lsof.txt 2>&1
lsof -n -P -l +L1 > /mnt/out/case/04-deleted-open.txt 2>&1
```

- *Footprint:* each `lsof` invocation spawns one static userland process reading
  `/proc/<pid>/fd`.

## 5. Unlocked volumes, live (`dflive send` → `dfnet stream`)

For every unlocked `/dev/mapper/<name>`, unlocked ZFS zvol (`/dev/zvol/...`), or
active software RAID/LVM volume whose key could not be extracted in hex in Step 2:

- **Authenticated stream to `dfnix` (`dfnet stream` + `dflive send`):**
  ```sh
  # On dfnix:
  dfnet stream --bind 10.0.0.1 -o /media/target/case01/live \
    -C "CASE" -E live01 -e "Examiner"
  # [*] Pairing code: 482 913 0576

  # On the Linux suspect (enter the 10-digit code shown by dfnet, or omit --code to be prompted):
  dflive send /dev/mapper/<name> --to 10.0.0.1:9998 --code "482 913 0576" \
    --log /mnt/out/case/dflive.jsonl
  ```
  `dflive` hashes what it reads while `dfnet stream` hashes what it stores into a
  `dfcore` collection (`manifest.json`, `items.jsonl`, `footprint.jsonl`,
  `items.csv`, audit anchor, verifiable with `dfcollect verify`). Unreadable
  sectors are replaced with zeros and listed by offset and length
  (`--stop-on-error` aborts at the first read error instead).
- **No network link available (local fallback to `/mnt/target`):**
  ```sh
  dd if=/dev/mapper/<name> of=/mnt/target/<name>.raw bs=4M status=progress conv=noerror,sync
  sha256sum /mnt/target/<name>.raw > /mnt/out/case/05-<name>.sha256
  ```
- **Encrypted ZFS datasets:** prefer streaming unlocked zvols (`/dev/zvol/...`) or
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

`/mnt/out/case/01-status.json` (Step 1) already lists running cloud sync clients
and known sync folders in each login profile without listing home directories.
Supplement with Kerberos tickets, active SSH/GPG sockets, and cloud/container
credential paths for the **§ 110 Abs. 3 StPO** decision:

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
4. On `dfnix`, verify the field-kit stick (`dfkit verify` or against
   `KIT-MANIFEST.sha256`) and check `/mnt/out/case/dflive.jsonl` to confirm
   `dflive_matches_kit: true` and account for every command and file written.
