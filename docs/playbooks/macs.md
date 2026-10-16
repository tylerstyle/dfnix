# Macs

Most Macs can't be imaged the classic way. On Apple silicon and on Intel Macs
with a T2 chip, the internal storage is encrypted in hardware, with or without
FileVault. A raw copy of the SSD would be ciphertext, and dfnix can't boot on
Apple silicon at all. What you can get depends on whether the Mac is running,
whether you have the password or a recovery key, and which chip it has.

## 1. Identify the Mac first

- Apple menu → About This Mac: "Chip: Apple M…" means Apple silicon, "Processor:
  Intel" means Intel.
- On an Intel Mac, System Information → Controller (or iBridge) shows whether
  it has a T2 chip.
- Powered off: the model number on the underside (A-number) tells the
  generation. Look it up; don't power the Mac on to find out.

## 2. Running and unlocked

Follow `live-macos.md`: the scene record, keys (`fdesetup`, `diskutil apfs`),
volatile state, then a logical acquisition with Fuji from the field kit (KIT-MAC)
to an external disk. This is the best moment you will get. Don't let the Mac lock
or sleep: once it is off, the data needs the password again.

## 3. Powered off

### Intel without T2 (about 2017 and older)

- Boot dfnix from USB (hold Option at power-on and choose the stick). If a
  firmware password stops you, you need the owner's firmware password.
- Image the internal disk with dfdisk, as for any PC.
- With FileVault, open the image, attached read-only with its partitions
  (`losetup -r -P -f --show image.raw` prints `/dev/loopN`):
  - macOS 10.13 and later (APFS, the usual case): `apfs-fuse` is read-only. It
    asks for the password (or recovery key) when the volume needs it:
    `apfs-fuse /dev/loopNpM /media/evidence/mac`. `-v N` selects a volume of the
    container; `apfsutil` lists the volumes and snapshots, and `-o snap=N`
    mounts a snapshot.
  - macOS 10.7–10.12 (FileVault 2 on Core Storage):
    `dfmount unlock --type fvault2 <partition>` with the password or recovery
    key.

### Intel with T2, and Apple silicon

External boot is off by default (Startup Security Utility). Changing that
needs an administrator's credentials, and it is a change to the Mac. Even then,
a raw image is ciphertext. Work logically instead, in recoveryOS, with the
password or the recovery key:

1. **Fuji in recoveryOS (preferred).** Start recoveryOS:
   - Apple silicon: hold the power button until "Loading startup options",
     then Options;
   - Intel T2: Command-R at power-on.

   Unlock the data volume with the password when asked, open Terminal from the
   Utilities menu, attach the field kit (KIT-MAC holds `Fuji.dmg`) and an
   external target disk. Run Fuji from there. Check the current Fuji
   documentation for its recoveryOS steps before you rely on them. Fuji makes a
   logical image with `asr`/`rsync` and records hashes.
2. **Share Disk (Apple silicon, macOS 12 and later).** In recoveryOS: Utilities
   → Share Disk, then choose the unlocked data volume. The Mac then serves the
   volume over SMB through a USB-C/Thunderbolt cable. This is file level: no
   APFS snapshots, no unallocated space, and the Mac runs an SMB server while
   you work. Apple documents a Mac on the other end. dfnix has not been tested
   as the client yet (needs `thunderbolt_net` and link-local IPv4). Until it
   is, use a forensic Mac as the client, or Fuji.
3. **Target Disk Mode (Intel T2).** The volume is readable over Thunderbolt
   only once it is unlocked with the password on the host Mac; again file level.

Without the password or a recovery key, there is no route to the data on these
Macs. Seize the device, keep it powered off and in a Faraday bag (so it can't be
wiped remotely when it next starts), and ask the owner or the service provider. The Mac may also back
up to iCloud or to a Time Machine disk, so look for those.

## 4. What not to do

- Don't change Startup Security, SIP, the firmware password or NVRAM unless
  the case requires it, and write down every change.
- Don't reset or "erase all content and settings". Don't install anything on
  the Mac.
- Don't let a Mac with an unknown password lock: if it is running and
  unlocked, finish `live-macos.md` first.
- Don't put a running, unlocked Mac to sleep "for transport". It will want the
  password again.

## 5. Record

- Model, chip, serial (from About This Mac or the underside) and macOS version.
- FileVault state (`fdesetup status`) and the route you took.
- The recoveryOS steps and every prompt you answered.
- For Fuji: its log and hashes. For Share Disk: the SMB session, and the
  `dfcollect files` collection on dfnix.
