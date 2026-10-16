# Live Acquisition Checklist: Running macOS System

Use this checklist when a Mac is found running and unlocked at the scene. Apple
silicon (M1/M2/M3/M4) and T2 Macs cannot boot `dfnix` directly, and their
internal storage is hardware-encrypted (Secure Enclave / T2), making live
acquisition or recoveryOS acquisition essential before power-off if the password
or recovery key is unknown.

Mount or use the `KIT-MAC` partition (`/Volumes/KIT-MAC`, HFS+ with Spotlight
and `fseventsd` disabled via `.metadata_never_index` and `.fseventsd/no_log`).
Write small outputs to `/Volumes/KIT-OUT` and large outputs to an external USB
target disk (`/Volumes/TARGET`), never to the suspect's internal volume.

> **Footprint & Warnings**
> - **Auto-mount:** `diskarbitrationd` mounts USB partitions automatically when
>   plugged in; `.metadata_never_index` and `.fseventsd/no_log` on `KIT-MAC` and
>   `KIT-OUT` keep Spotlight (`mds`) and `fseventsd` from indexing them.
> - **TCC / Privacy prompts:** Reading `~/Library/Mail`, `~/Desktop`, `~/Documents`,
>   or running `log collect` / UAC from `Terminal.app` may prompt the user to
>   grant Full Disk Access to Terminal if not already granted.
> - **iCloud & Find My tipping-off:** Opening iCloud settings or triggering
>   Apple Account authentication notifies the user's other Apple devices.

---

## 1. Record the scene

1. **Photograph the screen** (open windows, menu bar icons, active user, clock).
2. **Keep the Mac awake** (run in a Terminal tab for the duration of collection):
   ```sh
   caffeinate -dimsu &
   ```
   *Footprint:* spawns one `caffeinate` process holding power assertions in RAM.
3. **Record reference time vs. system clock** (compare with the examiner's UTC
   reference clock):
   ```sh
   mkdir -p /Volumes/KIT-OUT/case
   { date -u +"suspect_utc:   %Y-%m-%dT%H:%M:%SZ"
     date    +"suspect_local: %Y-%m-%dT%H:%M:%S%z"
     systemsetup -gettimezone -getusingnetworktime -getnetworktimeserver 2>&1
   } > /Volumes/KIT-OUT/case/01-clock.txt
   ```

## 2. Encryption state and key material (seconds — before memory on purpose)

Capture FileVault and APFS cryptographic state immediately while the volume is
unlocked:

```sh
{ fdesetup status
  fdesetup list -extended 2>&1
  diskutil list
  diskutil apfs list
  diskutil apfs listCryptoUsers /
  ls -la /Library/Keychains/FileVaultMaster.keychain 2>/dev/null
} > /Volumes/KIT-OUT/case/02-filevault-apfs.txt
```

- Check whether MDM / institutional recovery key escrow is configured
  (`fdesetup status` reports institutional or personal recovery keys).
- **Result:** If FileVault is On (or on any Apple silicon / T2 Mac, where media
  encryption is always active) and you do not hold a verified password or
  recovery key, **you must acquire the unlocked volume and artifacts in Steps 5–6
  before shutting down**.
- **Key material handling:** Treat `02-*` files on `/Volumes/KIT-OUT` (exFAT) as
  sensitive material (store the stick in a sealed evidence bag after the scene)
  until `dflive keys` encrypts them with `age`.
- *Footprint:* read-only queries to `diskarbitrationd` / `storagekitd`.

## 3. Memory

- **Apple silicon (M1/M2/M3/M4) and Intel Macs on current macOS:** **Do not
  attempt live kernel memory acquisition.** Neither Apple silicon nor Intel Macs
  running current macOS have a maintained, reliable open-source memory acquisition
  tool, and SWGDE warns that third-party kernel memory extensions cause kernel
  panics that immediately lock the FileVault / Secure Enclave volume. Record this
  in the case notes and proceed to Step 4:
  ```sh
  { uname -a
    sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model
    echo "RAM capture skipped: no reliable open-source macOS kernel memory tool (SWGDE panic warning)."
  } > /Volumes/KIT-OUT/case/03-memory-note.txt
  ```
- Sleep images and swap files (`/private/var/vm/sleepimage`, `swapfile*`) are
  collected in Step 6.

## 4. Volatile state

Capture network connections with PIDs, ARP/route tables, process tree with full
command lines, logged-in users, mounts, and LaunchDaemons/Agents:

```sh
{ netstat -anv
  lsof -i -n -P
} > /Volumes/KIT-OUT/case/04-network.txt 2>&1
arp -an > /Volumes/KIT-OUT/case/04-arp.txt
netstat -rn > /Volumes/KIT-OUT/case/04-routes.txt
scutil --dns > /Volumes/KIT-OUT/case/04-dns.txt 2>&1
ps auxww -o pid,ppid,uid,lstart,comm,args > /Volumes/KIT-OUT/case/04-processes.txt
{ who; echo "---"; last -20; } > /Volumes/KIT-OUT/case/04-users.txt
mount > /Volumes/KIT-OUT/case/04-mounts.txt
df -h >> /Volumes/KIT-OUT/case/04-mounts.txt
{ launchctl list
  sudo launchctl print system
} > /Volumes/KIT-OUT/case/04-launchd.txt 2>&1
```

- *Footprint:* runs standard macOS userland binaries (`netstat`, `lsof`, `ps`,
  `launchctl`); `sudo` logs an entry in the Unified Log.

## 5. Unlocked volumes, live (Fuji logical acquisition or `dflive send`)

Raw block imaging of `/dev/disk0` on a running T2 or Apple silicon Mac yields
ciphertext or inconsistent APFS state. Attach `Fuji.dmg` from `KIT-MAC`
**read-only** without Spotlight/Finder browsing and acquire to `/Volumes/TARGET`:

```sh
hdiutil attach -readonly -nobrowse -noverify /Volumes/KIT-MAC/Fuji.dmg
sudo /Volumes/Fuji/Fuji.app/Contents/MacOS/Fuji
```

- Use Fuji to acquire the unlocked Data volume (`/System/Volumes/Data` or `/`)
  via `asr` or `rsync` with metadata preservation and SHA-256 hashing to
  `/Volumes/TARGET`.
- For non-APFS unlocked volumes or disk images, stream to `dfnix` over a direct
  network link (`dfnet stream --bind 10.0.0.1 -o /media/target/case01/live -C ...`
  on `dfnix`, and `dflive send <source> --to 10.0.0.1:9998` once `dflive` for
  macOS is on the kit).
- **If the Mac is powered off and the password or recovery key is known:**
  1. Boot into **recoveryOS** (hold Power on Apple silicon, or `Cmd+R` on Intel),
     open Terminal, mount `KIT-MAC`, attach `Fuji.dmg` read-only, and run Fuji
     straight to an external disk (preferred).
  2. Or use recoveryOS **Share Disk** over Thunderbolt/Ethernet and acquire from
     `dfnix` using `dfnet smb` + `dfcollect files` (note: Share Disk is file-level
     SMB, omits APFS snapshots, and runs an SMB server on the Mac).

## 6. Artifacts (UAC + Unified Logs + VM files)

1. **Run UAC from its own directory on `KIT-MAC`** (upstream `uac` requires the
   working directory to be its root; collects plist configurations, FSEvents,
   Unified Log metadata, quarantine events, TCC.db, browser/shell history, and
   system state into a timestamped archive with accompanying SHA-256 manifest):
   ```sh
   (cd /Volumes/KIT-MAC/uac && sudo ./uac -p ir_triage /Volumes/TARGET/)
   ```
   *(Use `-p full` when time and target capacity permit a complete collection.)*
2. **Export the macOS Unified Log archive** and copy any sleep/swap files:
   ```sh
   sudo log collect --output /Volumes/TARGET/system_logs.logarchive
   sudo cp -p /private/var/vm/sleepimage /private/var/vm/swapfile* /Volumes/TARGET/ 2>/dev/null || true
   shasum -a 256 /Volumes/TARGET/system_logs.logarchive* /Volumes/TARGET/sleepimage /Volumes/TARGET/swapfile* > /Volumes/KIT-OUT/case/06-extra.sha256 2>/dev/null || true
   ```
- *Footprint:* `uac` creates a temporary working directory on `/Volumes/TARGET/`;
  `log collect` triggers `logd` to flush in-memory ring buffers into the archive.

## 7. Remote footprint on the device

Record signed-in iCloud / CloudDocs accounts, third-party sync folders, mail
stores, browser profiles, Keychains, cloud CLI credentials, and Kerberos tickets
for the **§ 110 Abs. 3 StPO** decision and provider orders:

```sh
klist > /Volumes/KIT-OUT/case/07-kerberos.txt 2>&1
ls -la /Users/*/Library/Mobile\ Documents \
       /Users/*/Library/CloudStorage \
       /Users/*/Dropbox /Users/*/OneDrive* \
       /Users/*/Library/Mail /Users/*/Library/Keychains \
       /Users/*/.aws /Users/*/.azure /Users/*/.config/gcloud \
       /Users/*/.kube /Users/*/.ssh \
       /Users/*/Library/Group\ Containers/*1password* \
       /Users/*/Library/Application\ Support/Bitwarden \
       > /Volumes/KIT-OUT/case/07-remote-footprint.txt 2>&1
```

- **Do NOT open iCloud/Mail or use active credentials to pull remote data**
  without specific legal authorization; isolate network interfaces once any
  local network transfer to `dfnix` is complete.

## 8. Shut down or pull the plug, and verify

1. **STOP — Gate before power-off:** Confirm that for every FileVault / Secure
   Enclave / encrypted volume you have either (a) a verified password or
   recovery key, or (b) a completed, hash-verified Fuji logical acquisition and
   artifact collection on `/Volumes/TARGET`. Powering off an Apple silicon or T2
   Mac without a known password/recovery key or completed live acquisition
   permanently locks the volume.
2. Detach `Fuji.dmg` and unmount the target and kit volumes cleanly:
   ```sh
   hdiutil detach /Volumes/Fuji 2>/dev/null || true
   sync
   diskutil unmount /Volumes/TARGET
   diskutil unmount /Volumes/KIT-OUT
   diskutil unmount /Volumes/KIT-MAC
   ```
3. Shut down (`sudo shutdown -h now`) or power off per policy. On Intel Macs
   without T2 (or with external boot allowed), image with `dfdisk`.
4. On `dfnix`, mount `KIT-MAC` read-only and verify all files against
   `KIT-MANIFEST.sha256` to confirm the suspect system modified no tool.
