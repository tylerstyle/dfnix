# Live Acquisition Checklist: Running Windows System

Use this checklist when a Windows computer is found running and unlocked at the
scene. All tools run directly from the `KIT-WIN` partition of the `dfnix`
field-kit stick (`D:\` in the examples below); write small scene/key outputs to
`KIT-OUT` (`E:\`) and memory/volume/artifact dumps to a dedicated external
target drive (`F:\`), never to `C:\`.

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

## 1. Record the scene

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
3. **Record reference time vs. system clock** (dfnix runs without NTP; record the
   examiner's reference UTC clock alongside the suspect's clock):
   ```bat
   mkdir E:\case
   powershell -NoProfile -Command "[pscustomobject]@{UtcNow=(Get-Date).ToUniversalTime().ToString('o');LocalNow=(Get-Date).ToString('o');TimeZone=(Get-TimeZone).Id} | Format-List" > E:\case\01-clock.txt
   w32tm /query /status >> E:\case\01-clock.txt 2>&1
   ```

## 2. Encryption state and key material (seconds — before memory on purpose)

Run this **before** memory acquisition: it takes seconds, whereas loading a
physical-memory driver can BSOD the machine and lose the encryption keys forever.
Note this deliberate deviation from strict order of volatility in your report.

### Built-in fallback (`manage-bde`, works even when App Control blocks kit binaries)

Run for `C:` and every fixed or removable volume (`mountvol` lists all volumes):

```bat
mountvol > E:\case\02-volumes.txt
manage-bde -status > E:\case\02-bitlocker-status.txt
manage-bde -protectors -get C: > E:\case\02-bitlocker-protectors-C.txt
```

- Check `02-bitlocker-protectors-C.txt` for the **48-digit Numerical Password**
  and Key Protector IDs. On `dfnix`, `dfmount unlock /dev/sdX3` (auto-detects
  BitLocker, or pass `--type bitlk`) prompts interactively for the 48-digit
  recovery password, or `--key-file <file>` reads a binary/recovery key file.
- If no recovery protector exists and the volume is unlocked, prefer streaming
  `\\.\C:` live in Step 5. Adding a recovery password on the suspect machine
  (`manage-bde -protectors -add C: -RecoveryPassword > E:\case\02-added-protector.txt`)
  **writes a new key protector into the volume's on-disk BitLocker metadata and
  logs an event in the BitLocker management log** — do this only as a documented
  modification after an explicit per-case legal/policy decision.
- Check for mounted **VeraCrypt / TrueCrypt / BitLocker To Go** containers:
  ```bat
  fltmc volumes >> E:\case\02-volumes.txt
  tasklist /fi "imagename eq VeraCrypt.exe" >> E:\case\02-volumes.txt
  ```
- **Key material handling:** `02-*` files on `KIT-OUT` (exFAT) contain plaintext
  recovery passwords. Treat the stick as sensitive key material (store in a
  sealed evidence bag after the scene) until `dflive.exe keys` encrypts them
  with `age`.

## 3. Memory

Record start and end timestamps (the **smear window**) and hash the dump.
`winpmem_mini_x64_rc2.exe` (~515 KiB) is preferred over the Go wrapper for its
smaller memory footprint and direct raw/ELF64 output for Volatility 3:

```bat
echo Start: %DATE% %TIME% > E:\case\03-mem-window.txt
D:\winpmem\winpmem_mini_x64_rc2.exe F:\physmem_%COMPUTERNAME%.raw >> E:\case\03-mem-window.txt 2>&1
echo End:   %DATE% %TIME% >> E:\case\03-mem-window.txt
certutil -hashfile F:\physmem_%COMPUTERNAME%.raw SHA256 > E:\case\03-mem.sha256
```

- **32-bit x86 Windows:** use `D:\winpmem\winpmem_mini_x86.exe`.
- **AFF4 compressed output:** `D:\winpmem\go-winpmem_amd64_1.0-rc2_signed.exe acquire --progress F:\physmem_%COMPUTERNAME%.aff4`.
- **HVCI / Core Isolation & Windows on Arm (`arm64`):** Windows 11 Memory
  Integrity (HVCI) or Microsoft's driver blocklist may refuse `winpmem_x64.sys`
  even though it carries a Microsoft WHCP signature, and no signed WinPmem driver
  exists for `arm64`. If driver load fails, record the error in `03-mem-window.txt`
  and continue immediately with Step 4 — do not reboot or disable HVCI.
- *Footprint:* extracts a temporary `.sys` driver, registers and starts the `pmem`
  kernel service (logged in `System.evtx` Event ID 7045), maps physical RAM, and
  unloads the service on exit.

## 4. Volatile state

Capture network sockets with owning PIDs, ARP/route/DNS caches, full process tree
with command lines and SHA-256 hashes, logged-in sessions, shares, and tasks:

```bat
netstat -abno > E:\case\04-netstat.txt
arp -a > E:\case\04-arp.txt
route print > E:\case\04-routes.txt
ipconfig /all > E:\case\04-ipconfig.txt
ipconfig /displaydns > E:\case\04-dnscache.txt
query user > E:\case\04-users.txt 2>&1
net session >> E:\case\04-users.txt 2>&1
net use > E:\case\04-shares.txt
net share >> E:\case\04-shares.txt
schtasks /query /fo LIST /v > E:\case\04-schtasks.txt
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,CreationDate,Name,ExecutablePath,CommandLine | Export-Csv -NoTypeInformation E:\case\04-processes.csv"
powershell -NoProfile -Command "Get-Process | Where-Object Path | Select-Object -Unique Path | ForEach-Object { Get-FileHash -Algorithm SHA256 $_.Path }" > E:\case\04-proc-hashes.txt
```

- *Footprint:* spawns built-in userland processes (`netstat`, `powershell`, etc.),
  consuming a few megabytes of RAM and logging process creation if Audit Process
  Creation (4688) is enabled. *(Replaced by `D:\dflive.exe state` once `dflive` is on the kit.)*

## 5. Unlocked volumes, live

If `C:` (or another encrypted volume such as VeraCrypt) is unlocked and no
offline recovery key could be captured in Step 2, acquire the volume while live:

- **Authenticated stream to `dfnix` (`dfnet stream` + `dflive send`, once `dflive.exe` is on the kit):**
  ```sh
  # On dfnix:
  dfnet stream --bind 10.0.0.1 -o /media/target/case01/live -C "CASE" -E live01 -e "Examiner"
  ```
  ```bat
  :: On the Windows suspect (using the 10-digit pairing code shown by dfnet):
  D:\dflive.exe send \\.\C: --to 10.0.0.1:9998 --code "123 456 7890" --log E:\case\05-dflive.jsonl
  ```
- Until `dflive.exe` is on the kit (or if no network link is available), ensure
  Step 6 completes in full to `F:\`.

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

Identify active cloud, mail, and credential material so the lead investigator can
make a **§ 110 Abs. 3 StPO** decision or issue provider preservation orders:

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
   / key from Step 2, or (b) a complete, hash-verified live volume image or
   artifact collection from Steps 5–6. Pulling the plug without one of these
   permanently locks the data.
2. Flush the output drives (Safely Remove Hardware for `E:\` and `F:\`).
3. **Pull the plug** (disconnect power / remove battery) for workstations/laptops
   to preserve pagefile, unallocated space, and volatile state on disk without
   running shutdown scripts; use graceful `shutdown /s /t 0` only when policy or
   cached storage controllers require it.
4. Boot `dfnix` (or remove the drive into a write-blocked adapter) and image all
   physical disks with `dfdisk`. Verify the field-kit stick on `dfnix` against
   `D:\KIT-MANIFEST.sha256` to confirm the suspect system modified no tool.
