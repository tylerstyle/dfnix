# Live Acquisition Checklist: Running Windows System

Use this checklist when a Windows computer is found running and unlocked at the
scene. All tools run directly from the `KIT-WIN` partition of the `dfnix`
field-kit stick (`D:\` in the examples below; Windows assigns drive letters
dynamically, so verify the volume label `KIT-WIN` in Explorer or `mountvol`):

- `D:\dflive.exe` — live companion (`status`, `keys`, `mem`, `state`, `send`).
  It is an `x86_64` console binary that links only Windows system DLLs; on
  **Windows on Arm (`arm64`)**, Windows 11 runs `D:\dflive.exe` under its
  built-in x64 emulation.
- `D:\winpmem\` — signed WinPmem memory dumpers (`winpmem_mini_x64_rc2.exe`,
  `winpmem_mini_x86.exe`, `go-winpmem_amd64_1.0-rc2_signed.exe`).
- `D:\velociraptor\` — Velociraptor offline collectors (`amd64` and `arm64`) and
  `collector-spec.yaml`.

Write small scene, key, state, and footprint records to `KIT-OUT` (`E:\` in the
examples below; adjust to match Windows' assigned drive letter for the `KIT-OUT`
volume) and memory, volume, or artifact dumps to a dedicated external target
drive (`F:\`), or stream them to `dfnix` over the network — never write to
`C:\`. Pass `--log E:\case\dflive.jsonl` on every `dflive.exe` run: each run
appends one JSON line recording `dflive.exe`'s own SHA-256, whether
`D:\KIT-MANIFEST.sha256` lists it with that hash, every child command and exit
code, every file written with its SHA-256, and the outcome.

> **Footprint & Warnings**
> - **USB traces:** Plugging in the stick writes device entries to
>   `HKLM\SYSTEM\CurrentControlSet\Enum\USBSTOR` and `C:\Windows\inf\setupapi.dev.log`.
>   Record the stick's serial number so these entries can be attributed in the report.
> - **EDR / SOC tipping-off:** Running unsigned binaries, loading the WinPmem
>   kernel driver, or reading raw NTFS volumes can trigger Windows Defender,
>   Smart App Control, AppLocker, or enterprise EDR alerts to a remote SOC.
> - **BitLocker & UEFI boot changes:** Changing Secure Boot or UEFI boot order
>   to boot `dfnix` alters TPM PCRs and can force BitLocker recovery on the next
>   boot. Capture the 48-digit recovery password in Step 2 before touching UEFI.

---

## 1. Record the scene (`dflive.exe status`)

1. **Photograph the screen** showing open applications, active network/VPN icons,
   logged-in user, and the system tray clock.
2. **Keep the machine awake:** attach a hardware USB mouse jiggler, or from an
   elevated Command Prompt (`cmd.exe` as Administrator) disable sleep/lock:
   ```bat
   powercfg /change standby-timeout-ac 0
   powercfg /change standby-timeout-dc 0
   powercfg /change monitor-timeout-ac 0
   powercfg /change hibernate-timeout-ac 0
   ```
   *Footprint:* modifies the active power scheme in the registry.
3. **Record the scene and clock offset** against a trusted reference clock
   (radio clock, phone) typed as RFC 3339 with offset:
   ```bat
   mkdir E:\case
   D:\dflive.exe status --reference-time 2026-10-16T17:05:00+02:00 -o E:\case\01-status.json --log E:\case\dflive.jsonl
   ```
   `01-status.json` records the system clock and its offset in seconds against
   `--reference-time`, OS version and build, time zone, boot time, logged-in
   users, whether `dflive.exe` runs elevated, disks and volumes (model, serial,
   size, mounts, network drives), BitLocker status at a glance
   (`manage-bde -status`), and running cloud sync clients (`OneDrive`, `Dropbox`,
   `Google Drive`, `iCloud`, `Nextcloud`, etc.) together with their folders
   (found by looking up known names in each user profile, without listing user
   directories).

## 2. Encryption state and key material (`dflive.exe keys` — before memory on purpose)

Run this **before** memory acquisition: it takes seconds, whereas loading a
physical-memory driver can BSOD the machine and lose the encryption keys forever.
Note this deliberate deviation from strict order of volatility in your report.

```bat
D:\dflive.exe keys -o E:\case\02-keys.json.age --recipient age1... --log E:\case\dflive.jsonl
```

- `dflive.exe keys` runs `manage-bde -status` and `manage-bde -protectors -get`
  for every detected volume (capturing the **48-digit Numerical Password** and
  Key Protector IDs) and seals the JSON document to the examiner's `age` X25519
  public key (`--recipient`, repeatable) before writing, so recovery passwords
  never lie in plain text on `KIT-OUT`.
- If no examiner `age` public key is at hand, pass `--plaintext`:
  ```bat
  D:\dflive.exe keys -o E:\case\02-keys.json --plaintext --log E:\case\dflive.jsonl
  ```
  Treat the stick as sensitive key material and store it in a sealed evidence bag
  after the scene.
- On `dfnix`, decrypt with `age -d -i examiner.key -o 02-keys.json <KIT-OUT>/case/02-keys.json.age`;
  `dfmount unlock /dev/sdX3` (auto-detects BitLocker, or pass `--type bitlk`)
  prompts interactively for the 48-digit recovery password, or
  `--key-file <file>` reads a binary/recovery key file.
- If no recovery protector exists and the volume is unlocked, prefer streaming
  `\\.\C:` live in Step 5. Adding a recovery password on the suspect machine
  (`manage-bde -protectors -add C: -RecoveryPassword > E:\case\02-added-protector.txt`)
  **writes a new key protector into the volume's on-disk BitLocker metadata and
  logs an event in the BitLocker management log** — do this only as a documented
  modification after an explicit per-case legal/policy decision.
- Check for mounted **VeraCrypt / TrueCrypt / BitLocker To Go** containers:
  ```bat
  fltmc volumes > E:\case\02-volumes.txt
  tasklist /fi "imagename eq VeraCrypt.exe" >> E:\case\02-volumes.txt
  ```
- **Built-in fallback (only if Smart App Control or AppLocker blocks `dflive.exe`):**
  ```bat
  mountvol > E:\case\02-volumes.txt
  manage-bde -status > E:\case\02-bitlocker-status.txt
  manage-bde -protectors -get C: > E:\case\02-bitlocker-protectors-C.txt
  ```

## 3. Memory (`dflive.exe mem`)

`dflive.exe mem` invokes `WinPmem` (`winpmem_mini_x64_rc2.exe`) from `KIT-WIN`,
hashes the resulting dump, and writes `F:\physmem_%COMPUTERNAME%.raw.json` next
to it with the tool's SHA-256, the exact command, the capture window (`started`
to `finished`, since memory changes while it is read), the exit status, and the
dump's size and SHA-256:

```bat
D:\dflive.exe mem -o F:\physmem_%COMPUTERNAME%.raw --log E:\case\dflive.jsonl
```

- **32-bit x86 Windows:** run `D:\winpmem\winpmem_mini_x86.exe F:\physmem_%COMPUTERNAME%.raw`
  directly and hash with `certutil -hashfile F:\physmem_%COMPUTERNAME%.raw SHA256`.
- **AFF4 compressed output:** `D:\winpmem\go-winpmem_amd64_1.0-rc2_signed.exe acquire --progress F:\physmem_%COMPUTERNAME%.aff4`.
- **HVCI / Core Isolation & Windows on Arm (`arm64`):** Windows 11 Memory
  Integrity (HVCI) or Microsoft's driver blocklist may refuse `winpmem_x64.sys`
  even though it carries a Microsoft WHCP signature, and no signed WinPmem driver
  exists for `arm64`. If driver load fails, `dflive.exe mem` records the failure
  in `F:\physmem_%COMPUTERNAME%.raw.json` and `dflive.jsonl` (exit 4) — continue
  immediately with Step 4 and do not reboot or disable HVCI.
- *Footprint:* extracts a temporary `.sys` driver, registers and starts the `pmem`
  kernel service (logged in `System.evtx` Event ID 7045), maps physical RAM, and
  unloads the service on exit.

## 4. Volatile state (`dflive.exe state`)

`dflive.exe state` reads the volatile state with its own Windows API calls
(Toolhelp, IP Helper, WTS, Service Control Manager, `psapi`,
`NtQueryInformationProcess`) rather than spawning the suspect's possibly
tampered `tasklist`, `netstat`, or `query user`:

```bat
D:\dflive.exe state -o E:\case\04-state.json --log E:\case\dflive.jsonl
```

`04-state.json` records:
- processes with PID, PPID, start time, command line, owner (SID and account),
  and executable SHA-256 (`--no-hash` skips hashing executables);
- TCP and UDP endpoints (IPv4 and IPv6) with owning PIDs;
- network adapters with IPv4/IPv6 addresses, gateways, and DNS servers;
- IPv4/IPv6 routing table and neighbour (ARP/NDP) cache;
- logon sessions (console and RDP, with client name and address);
- running Win32 services and active kernel drivers with their PIDs/paths, plus
  loaded kernel images;
- OS version, time zone, boot time, and whether NTFS updates last-access times
  (because hashing reads every process image).

## 5. Unlocked volumes, live (`dflive.exe send` → `dfnet stream`)

If `C:` (or another encrypted volume such as VeraCrypt, or a whole disk
`\\.\PhysicalDrive0`) is unlocked and no offline recovery key could be captured
in Step 2, stream it over an authenticated, encrypted `dfstream/1` connection
(SPAKE2 pairing + ChaCha20-Poly1305) to `dfnix`:

```sh
# On dfnix:
dfnet stream --bind 10.0.0.1 -o /media/target/case01/live \
  -C "CASE" -E live01 -e "Examiner"
# [*] Pairing code: 482 913 0576
```

```bat
:: On the Windows suspect (enter the 10-digit code shown by dfnet, or omit --code to be prompted):
D:\dflive.exe send \\.\C: --to 10.0.0.1:9998 --code "482 913 0576" --log E:\case\dflive.jsonl
```

- `dflive.exe` hashes what it reads while `dfnet stream` hashes what it writes
  into a `dfcore` collection (`manifest.json`, `items.jsonl`, `footprint.jsonl`,
  `items.csv`, audit anchor, verifiable with `dfcollect verify`). Unreadable
  sectors on a disk or volume are replaced with zeros and listed by offset and
  length (`--stop-on-error` aborts on the first read error instead).
- **No network link available:** ensure Step 6 (Velociraptor offline collector to
  `F:\`) completes in full so locked system artifacts and user data are preserved
  on `F:\`.

## 6. Artifacts (Velociraptor offline collector)

`KIT-WIN` carries Velociraptor (`amd64` and `arm64`) plus `collector-spec.yaml`,
which reads locked files (`$MFT`, `$UsnJrnl:$J`, `$LogFile`, Registry hives,
Event Logs, SRUM, Amcache, Prefetch, LNK/JumpLists) directly through its raw
NTFS parser without creating a Volume Shadow Copy:

```bat
mkdir F:\temp
D:\velociraptor\velociraptor-windows-amd64.exe --config D:\velociraptor\collector-spec.yaml artifacts collect DFNIX.Windows.Triage --require_admin --nobanner --tempdir F:\temp --output F:\velo_%COMPUTERNAME%.zip
certutil -hashfile F:\velo_%COMPUTERNAME%.zip SHA256 > E:\case\06-velo.sha256
```

- On **Windows on Arm (`arm64`)**, substitute `velociraptor-windows-arm64.exe`.
- To build a zero-argument self-contained `.exe` before going on scene, see
  `D:\velociraptor\REPACK.md` (`velociraptor config repack --exe ...`).
- *Footprint:* opens `\\.\C:` read-only and writes temporary files to `F:\temp`.

## 7. Remote footprint on the device

`E:\case\01-status.json` (Step 1) already lists running cloud sync clients and
known sync folders (`OneDrive`, `Dropbox`, `Google Drive`, `iCloudDrive`,
`Nextcloud`, `ownCloud`, `MEGA`, `Box`, `Syncthing`, `pCloud Drive`, `Tresorit`,
`SynologyDrive`, `Seafile`, `.config/rclone/rclone.conf`) in each user profile
without listing user directories. Supplement with Kerberos tickets, stored
credentials, and mail/cloud/password-manager AppData and CLI directories (names
and timestamps only) so the lead investigator can make a **§ 110 Abs. 3 StPO**
decision or issue provider preservation orders:

```bat
klist > E:\case\07-kerberos.txt 2>&1
cmdkey /list > E:\case\07-cmdkey.txt 2>&1
powershell -NoProfile -Command "Get-ChildItem C:\Users\*\AppData\Local\Microsoft\OneDrive,C:\Users\*\AppData\Local\Dropbox,C:\Users\*\AppData\Local\Google\DriveFS,C:\Users\*\AppData\Local\Packages\*iCloud*,C:\Users\*\AppData\Local\Microsoft\Outlook,C:\Users\*\AppData\Roaming\Thunderbird,C:\Users\*\.aws,C:\Users\*\.azure,C:\Users\*\.kube,C:\Users\*\.ssh,C:\Users\*\AppData\Local\1Password,C:\Users\*\AppData\Roaming\Bitwarden -Force -ErrorAction SilentlyContinue | Select-Object FullName,LastWriteTime" > E:\case\07-remote-footprint.txt
```

- **Do NOT open cloud/mail apps or access remote data automatically:** doing so
  can send login alerts, trigger MFA prompts on the suspect's phone, or sync
  remote deletions onto the machine. Isolate networking once live transfers end.

## 8. Shut down or pull the plug, and image with `dfdisk`

1. **STOP — Gate before power-off:** Confirm that for **every** encrypted volume
   (BitLocker, VeraCrypt, etc.) you have either (a) a verified recovery password
   / key from Step 2, or (b) a complete, hash-verified live volume stream or
   artifact collection from Steps 5–6. Pulling the plug without one of these
   permanently locks the data.
2. Flush the output drives (Safely Remove Hardware for `E:\` and `F:\`).
3. **Pull the plug** (disconnect power / remove battery) for workstations/laptops
   to preserve pagefile, unallocated space, and volatile state on disk without
   running shutdown scripts; use graceful `shutdown /s /t 0` only when policy or
   cached storage controllers require it.
4. Boot `dfnix` (or remove the drive into a write-blocked adapter) and image all
   physical disks with `dfdisk`. Verify the field-kit stick on `dfnix` (`dfkit verify`
   or `KIT-MANIFEST.sha256`) and check `E:\case\dflive.jsonl` to confirm
   `dflive_matches_kit: true` and account for every command and file written.
