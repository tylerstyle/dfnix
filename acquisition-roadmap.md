# dfnix: Acquisition Roadmap

**Date:** 2026-10-16
**Status:** Draft, joint work of Claude Code (dfnix-claude) and Antigravity (agy);
maintainer decisions of 2026-10-16 included (§9)
**Scope:** acquisition only (identify, collect, acquire, preserve). Analysis is
left to the examiner's suites. iOS and Android are out of scope; other tools
cover them.

---

## 1. Where we stand

dfnix is good at one job today: imaging powered-off storage safely. Write-blocking,
the protected-device registry, dfdisk's verified E01/raw images, the hash-chained
audit log and dfmount's no-replay mounts make that path solid.

Casework increasingly breaks on the other paths:

1. **The machine is running and encrypted.** New Windows 11 installs turn on
   BitLocker device encryption by default, Apple silicon Macs can't be imaged
   powered off at all, and a LUKS server forgets its key when the power goes.
   Pulling the plug often ends the investigation. There is nothing on the dfnix
   stick for a running Windows, macOS or Linux system.
2. **The evidence isn't on a local disk.** Mailboxes, cloud drives, databases,
   virtual machines and NAS shares need the same discipline as disk imaging:
   read-only access, a hash per item, a record of the scope, and a record of
   what the acquisition changed on the source.
3. **There is no audited logical acquisition.** dfmount and dfnet hand the
   examiner a read-only mount and stop. Copying from it with `cp`, `rsync` or
   `rclone` produces no manifest, no scope record, no read-error accounting and
   no audit entry. (agy calls this "the rsync cliff".)

### Gaps in detail

| Situation | Today | Gap |
| --- | --- | --- |
| Powered-off PC or removable disk | dfdisk E01/raw, rescue | Solved. Secure Boot keeps dfnix off many laptops (IDEAS.md). |
| Running Windows with BitLocker | Nothing for Windows | No key capture, no memory capture, no live volume imaging |
| Running Mac, Apple silicon | Nothing | dfnix can't boot there; needs live logical acquisition or Share Disk |
| Running Linux server, LUKS/LVM | `dfnet receive` + manual `dd \| nc` | Unauthenticated stream, size must be known up front, no memory tool, no checklist |
| Mounted filesystem or SMB/NFS share | dfmount / `dfnet smb`, `dfnet nfs` | No audited copy: no manifest, scope or audit record |
| NAS, md-RAID, LVM, ZFS | dfmount refuses RAID members (correctly) | No read-only reconstruction; no ZFS in the kernel |
| Encrypted evidence volumes | Tools packaged, dfmount refuses them | No guided read-only unlock that preserves source identity and the audit chain |
| Server in a rack | Boot the ISO if USB works | No headless/serial mode, BMC virtual media untested, no remote read-only export |
| VMs on ESXi, Proxmox, Hyper-V | Nothing specific | No snapshot/memory procedure; VMFS 6 unreadable with packaged tools |
| Mailboxes (IMAP, Microsoft 365, Google) | Nothing forensic | No tool that guarantees `EXAMINE`/`BODY.PEEK`, scope and per-message hashes |
| Cloud drives, SharePoint, Nextcloud, S3 | rclone packaged | No read-only enforcement, manifest or provider-hash check |
| Databases | Nothing | No consistent-dump procedure, no clients, no manifests |
| Network traffic at the scene | tcpdump, tshark, zeek | No rotation + hash + drop-counter record |
| Provider deliveries (e-Evidence) | Nothing | No receipt and verification record |

---

## 2. Approach

**Self-reliant, open source only.** No step depends on a proprietary tool
(§9.4). Mature open-source tools stay: Velociraptor's offline collector, UAC,
AVML, WinPmem, Fuji, rclone and Fox-IT's acquire/dissect are maintained and used
in court, and rewriting them would cost years. Nix builds them from source and
pins them. Only two come as pinned upstream releases: WinPmem, whose kernel
driver must carry Microsoft's signature, and Fuji, a macOS app. The steps a case
depends on run on df code alone: scene record, key capture, volatile state,
streaming and logical acquisition. The collectors add breadth on top. We build
df code where nothing fits:

- forensic semantics around existing transports: read-only primitives, scope,
  manifests, footprint records, audit entries;
- authenticated streaming from a running system into dfnix;
- mail and service acquisition with the right protocol behaviour;
- read-only unlock and RAID/VM reconstruction that keep dfnix's guarantees;
- tests that prove the source stayed unchanged.

### The pieces

```
 running suspect system                    dfnix (live ISO / appliance / workstation)
 ┌────────────────────────────────┐         ┌─────────────────────────────────────────┐
 │ field-kit stick (one part./OS) │  auth.  │ dfnet receive v2 ─► raw / E01           │
 │  dflive status/keys/state/send │ ──────► │ dfdisk     physical imaging (as today)  │
 │  WinPmem, AVML  (memory)       │ stream  │ dfmount    + unlock, + assemble (ro)    │
 │  Velociraptor collector, UAC,  │   or    │ dfcollect  files, mail, cloud, db (NEW) │
 │  acquire, Fuji  (artifacts)    │ USB disk│ dfnet      + pcap                       │
 └────────────────────────────────┘         │ dfcore     manifest + scope + audit     │
                                            └─────────────────────────────────────────┘
```

Two new tools, both in their own repositories like the others:

- **`dfcollect`**: logical acquisition on dfnix. Files from any mount, mail,
  cloud services, databases. One tool, so manifest, scope and report code exist
  once. It is to logical data what dfdisk is to block devices.
- **`dflive`**: a small static companion for the running suspect system
  (Windows, Linux, macOS; x86_64 and arm64). It records the scene, captures
  encryption state, key material and volatile state, calls the memory tools,
  and streams to dfnix. It does not reimplement artifact collection.

(Names are proposals. agy's draft used `df-live`; `dflive` matches dfdisk/dfmount/dfnet/dfinfo.)

---

## 3. Evidence sources and the best approach for each

### 3.1 Powered-off storage

dfdisk stays as it is. Additions around it:

- **RAID, NAS, LVM, ZFS.** Image every member disk with dfdisk first, recording
  serials and bay order. Then reconstruct *from the images*, read-only:
  `losetup -r`, `mdadm --assemble --readonly`, LVM with
  `global/metadata_read_only = 1` and `activation/read_only_volume_list`,
  `zpool import -o readonly=on -o cachefile=none -N -R /media/evidence/zfs_<pool>`,
  btrfs multi-device `ro,rescue=nologreplay`. Synology SHR is md + LVM; QNAP is
  md + LVM thin (`thin-provisioning-tools`). Assembling the original disks is a
  fallback for triage only, with the read-only flags verified first. Belongs in
  **dfmount** (`dfmount assemble`).
  - ZFS in dfnix needs a lockdown, not just the module: NixOS requires a fixed
    `networking.hostId`, and its ZFS module enables TRIM, import/mount/share/ZED
    services and a `zpool sync` shutdown hook. Disable TRIM, mask those units,
    don't force-import, and add `zd*` (ZVOLs) to the udev read-only rule.
  - `mdadm` itself isn't installed today (`boot.swraid` is forced off); add the
    package without re-enabling the module's auto-assembly.
- **Hardware RAID.** Boot dfnix on the server so the controller presents the
  logical volume, image that, and record what Linux exposes about the
  controller. smartctl reaches the member disks behind most controllers
  (`-d megaraid,N`, `-d cciss,N`, `-d aacraid,H,L,ID`) for serials and SMART.
  Image the members as well when time allows: `mdadm` reads the SNIA DDF and
  Intel IMSM metadata that several controllers and Intel RST write, so such
  arrays can be rebuilt from the member images. Vendor CLIs (storcli, perccli,
  ssacli) are proprietary and out of scope (§9.4). For other on-disk layouts, a
  stripe-size and disk-order detector in `dfmount assemble` is a P3 idea.
- **Encrypted evidence volumes.** `dfmount unlock` opens them read-only with
  the key or recovery password, using cryptsetup for all of them: LUKS
  (`--type luks`), BitLocker (`--type bitlk`), VeraCrypt (`--type tcrypt
  --veracrypt`) and FileVault 2 (`--type fvault2`), each with `--readonly`.
  `dislocker -r` + `losetup -r` stays as fallback for metadata cryptsetup can't
  read. dfmount checks the backing disk against the registry first, verifies the
  mapped device is read-only, and logs a `volume_unlock` record. A dm-crypt
  mapping keeps its sysfs `slaves/` link, so dfdisk and dfcore resolve it to the
  physical disk as they do today; only the FUSE/loop fallback loses that link and
  needs a small mapping file (`/run/dfnix/unlocked.json`). Unlocked volumes must
  **not** go into `/run/dfnix/protected.json`: that registry lists system disks
  and the live medium, and every tool refuses what's in it.
- **Self-encrypting drives (TCG Opal).** dfdisk records the locking state
  (`sedutil-cli --query`) and warns: a locked drive answers the shadow-MBR range
  and fails the rest with read errors. Unlocking needs the password and changes
  the drive's locking state; document it. Never run sanitize or format commands.
- **VMFS 6 and exotic containers.** Fox-IT's **dissect** (in nixpkgs as
  `python3Packages.dissect`, `-target`, `-vmfs`, `-volume`, `-hypervisor`)
  reads VMFS, VMDK, VHDX and more from images.
- **Volume shadow copies, FileVault 2, LUKS offline.** The libyal tools
  (libvshadow, libfvde, libluksde, libvmdk, libvhdi) aren't in nixpkgs; package
  them in `dfnix/pkgs/`.
- **Intel VMD / RST laptops and server HBAs.** NVMe behind VMD is only visible
  with the `vmd` module. Add `vmd` and the HBA/RAID drivers missing from the
  initrd today (`megaraid_sas`, `mpt3sas`, `smartpqi`, `aacraid`; `hpsa` is
  already there) to `boot.initrd.availableKernelModules`, so these disks
  enumerate in stage 1 under the initrd write-blocking rules, before the
  protected-device registry is built, rather than late in stage 2. Verify on
  real hardware.
- **Macs.** Intel Macs with a T2 chip refuse external boot by default, and
  dfnix can't boot on Apple silicon at all. Decision tree:
  1. Running and unlocked: live acquisition (§3.2), logical via Fuji.
  2. Off, password or recovery key known, in recoveryOS:
     - run **Fuji** from the field kit in the recoveryOS Terminal, imaging
       with `asr`/`rsync` straight to an external disk (preferred; check the
       current Fuji documentation for recoveryOS support);
     - or use **Share Disk**, which exposes the unlocked volume over SMB (file level,
       not block level; it loses APFS snapshots and runs an SMB server on the
       Mac); acquire with `dfnet smb` + `dfcollect files`. Over a Thunderbolt
       cable dfnix needs `thunderbolt_net` and IPv4 link-local addressing.
       Apple documents Share Disk for a Mac on the other end; access from
       Linux is to be tested (P2).
  3. T2 Target Disk Mode: the volume is readable over Thunderbolt only once
     unlocked.
- **Secure Boot.** Still the main obstacle to imaging without removing the
  disk (see IDEAS.md). Changing Secure Boot or the boot order can trigger
  BitLocker recovery on the next Windows boot; the playbook must warn.

### 3.2 Running computers (the biggest gap)

Order at the scene, for Windows, macOS and Linux:

1. **Record the scene.** Screen photo, keep the machine awake, reference time vs.
   system clock.
2. **Encryption state and key material (seconds).** This comes before memory on
   purpose: it is fast, and a memory driver can crash the machine and take the
   keys with it. It deviates slightly from strict order of volatility; the
   report says so.
   - Windows: `manage-bde -status`, `manage-bde -protectors -get` per volume
     (recovery passwords, protector IDs); mounted VeraCrypt volumes.
   - Linux: `cryptsetup status`, `dmsetup table --showkeys`, LUKS header
     backups, `/etc/crypttab`, ZFS key status. LUKS2 keeps the volume key in
     the kernel keyring by default, so `--showkeys` often shows only a keyring
     reference. Then the key is in memory (step 3) and the unlocked
     `/dev/mapper` device can be imaged live (step 5).
   - macOS: `fdesetup status`, `diskutil apfs list`, `diskutil apfs
     listCryptoUsers`; escrowed or institutional recovery keys.
   - Result: "volume X is encrypted and currently unlocked: acquire it now".
3. **Memory.** Windows: WinPmem (Apache-2.0). Linux: AVML (MIT, static, in
   nixpkgs; no kernel module to build, unlike LiME). macOS on Apple silicon: no
   reliable tool, and SWGDE warns of kernel panics; record that and move on.
   Record start and end time of the capture (smear window) and skipped ranges.
   Volatility 3 needs a symbol table for Linux: dwarf2json is packaged; evaluate
   building ISF from BTF for kernels without debug symbols.
4. **Volatile state.** Connections with owning processes, ARP/route/DNS cache,
   process tree with command lines and hashes, logged-in users, mounts and
   network drives, scheduled tasks/cron/LaunchDaemons. Read by dflive's own
   code, not by the suspect's possibly tampered `netstat` or `ps`.
5. **Unlocked volumes, live.** Stream `\\.\C:` or `/dev/mapper/...` to dfnix,
   or collect logically when imaging isn't possible (APFS via Fuji).
6. **Artifacts.** Windows: Velociraptor offline collector (AGPL, built from
   source; reads locked files through its own NTFS parser, KAPE-style target
   sets). Linux, macOS,
   BSD, ESXi, NAS: UAC (Apache-2.0, plain shell). Cross-platform alternative:
   Fox-IT acquire (AGPL, in nixpkgs). macOS extra: `log collect`, sleepimage
   and swap files.
7. **Remote footprint on the device.** Signed-in sync clients (OneDrive,
   Dropbox, Google Drive, iCloud), mail accounts, browser profiles, password
   managers, crypto wallets, cloud CLI credentials, Kerberos tickets. dflive
   *reports* them for the § 110 Abs. 3 StPO decision and for provider orders.
   Using a live session or captured credentials to reach remote data is a
   per-case legal decision; the tools don't act on it by themselves.
8. Then shut down or pull the plug, per policy, and image with dfdisk.

**What dflive does:**

- `dflive status`: read-only scene record (clock vs. entered reference time,
  OS build, uptime, users, disks and volumes, encryption state, sync clients).
- `dflive keys`: protectors and recovery material as above, written to the
  output medium, optionally encrypted to the examiner's public key (`age`).
  It uses the OS interfaces directly where they exist (the BitLocker WMI class
  `Win32_EncryptableVolume`, device-mapper ioctls) and the system tools
  otherwise; either way the footprint log records what ran.
- `dflive mem`: runs WinPmem or AVML with timing and streaming SHA-256.
- `dflive state`: the volatile state of step 4, through `/proc` and sysfs on
  Linux, the Windows APIs, and `libproc`/`sysctl` on macOS.
- `dflive send <disk|volume|file>`: streams to `dfnet receive` over an
  authenticated channel, hashing at the source.
- A footprint log of its own actions: binary hash, every child command with
  exit code, files written, drivers loaded (WinPmem creates a service).
- No installation, nothing written to the suspect disk. Output goes to the
  kit's output partition, a separate USB target, or over the network.

**The field-kit stick.** It is a stick of its own, not a partition of the dfnix
stick (§9.5), and it carries one partition per target OS. Each partition uses
a filesystem that OS mounts without extra drivers:

| # | Label | Filesystem, GPT type | Used on | Contents |
| --- | --- | --- | --- | --- |
| 1 | `KIT-WIN` | NTFS, basic data | Windows | dflive.exe (x64, arm64), WinPmem, Velociraptor collector, checklists |
| 2 | `KIT-MAC` | HFS+, Apple HFS+ | macOS, also recoveryOS | dflive (arm64, x86_64), the upstream `Fuji.dmg` (attached read-only), checklists |
| 3 | `KIT-LNX` | ext4, Linux data | Linux, NAS, appliances | dflive and AVML (static musl via `pkgsStatic`, x86_64, aarch64), UAC with a static busybox in its `bin/` directory, checklists |
| 4 | `KIT-OUT` | exFAT, basic data, rest of the stick | all three | empty; status, keys and small outputs |

- `KIT-WIN` comes first: Windows before 10 version 1703 shows only the first
  partition of a removable stick. Output then goes to a second drive or over
  the network. The same applies to Linux kernels older than 5.7, which have no
  native exFAT.
- Correct GPT type codes keep Windows from assigning a drive letter to the ext4
  and HFS+ partitions and offering to format them.
- Nothing keeps the tool partitions read-only on every system, so the kit
  doesn't rely on it:
  - Windows honours the GPT read-only attribute (bit 60) only on disks that
    report themselves as fixed. Ordinary thumb drives report as removable, and
    Windows mounts their NTFS read-write. USB SSD sticks that report as fixed
    are therefore preferred: they also show all partitions on old Windows.
  - macOS (`diskarbitrationd`) and desktop Linux (`udisks2`) mount the
    partitions read-write as soon as the stick is plugged in.
  - The build marks the tool files immutable or read-only where the filesystem
    allows it.
  - The build puts `.metadata_never_index` and `.fseventsd/no_log` on
    `KIT-MAC` and `KIT-OUT`, so Spotlight and `fseventsd` stay off them.
- Memory dumps and volume images are too big for the stick: they go to a
  separate output drive or stream to dfnix.
- Each partition holds a `KIT-MANIFEST.sha256`, and the whole kit carries a
  signed manifest. dflive logs its own hash and the kit version on every run.
- `nix build .#fieldkit` builds the stick as a disk image. `mkfs.ext4 -d`
  fills `KIT-LNX` directly. NTFS and HFS+ can't be filled without mounting
  them, so a small build VM does that; it needs KVM, as the nixosTests already
  do. The image is reproducible at the file level, and its manifest covers
  every file.
- **`dfkit`** runs on dfnix and writes the image to one or several sticks at
  once:
  - It refuses protected devices, and each stick must be unblocked like any
    target.
  - It grows `KIT-OUT` to fill each stick and writes a kit ID (kit version and
    stick serial).
  - It reads every stick back, verifies it, and logs a `fieldkit_write` record
    with the stick's serial. Plugging the stick in leaves USB traces on the
    suspect system (on Windows, `USBSTOR` and `setupapi.dev.log`), and the
    report can then match them to the stick.
- **One kit per case.** After the deployment, `dfkit verify` mounts the tool
  partitions read-only on dfnix and re-hashes every file against the manifests,
  to show the suspect system changed no tool. A read-write mount changes
  filesystem metadata, so it compares files, not whole partitions, and lists
  files the OS added (`System Volume Information`, `.fseventsd`) separately.
  `dfcollect files` then takes `KIT-OUT` into the case, and the stick is
  rewritten before its next use.

### 3.3 Servers, hypervisors, containers

- **dfnix headless/server mode.** Boot through BMC virtual media (iDRAC, iLO,
  XClarity, IPMI), serial console, text mode, optional SSH into dfnix with a
  per-case key (off by default) so the examiner can run imaging from a laptop.
  Validate HBA/RAID drivers (megaraid_sas, mpt3sas, smartpqi, hpsa, aacraid)
  and 10/25 GbE NICs on the ISO.
- **Read-only iSCSI export.** dfnix exports evidence disks as read-only iSCSI
  LUNs over a direct link. The examiner's machine, for example a dfnix
  workstation with dfdisk, then images them while the server side enforces
  read-only and logs the session.
  The initiator only sees a virtual `LIO-ORG` disk, so dfnix first records the
  physical identity, SMART and hidden areas locally (`dfdisk check`) and passes
  the physical serial into the LUN's inquiry data.
- **Netboot.** An iPXE/PXE artifact for servers without usable USB.
- **VMware ESXi.** `govc` (in nixpkgs): snapshot *with memory* (`.vmsn`/`.vmem`
  hold guest memory without touching the guest), then download `.vmx`, NVRAM
  and the VMDK chain, hashing every file. UAC for host artifacts. ESXi keeps logs
  on a ramdisk unless scratch or syslog is configured: collect them before any
  reboot. Creating and removing snapshots writes to the datastore; record it.
- **Proxmox / KVM.** Guest memory as ELF via `virsh dump --memory-only` or
  QEMU `dump-guest-memory` (readable by Volatility), then the qcow2, ZFS or
  LVM-thin volumes with their snapshot chain.
- **Hyper-V.** Hyper-V defaults to *production* checkpoints (VSS inside the
  guest, no memory). For memory state, check or set `CheckpointType Standard`
  (a configuration change: footprint) and take a standard checkpoint, then
  `Export-VM` or copy the `.vhdx`/`.avhdx` chain; offline from a dfmount'ed
  host volume.
- **Containers.** Before stopping: `docker inspect`/pod spec, container logs,
  process and network namespace state, the overlay upper layer
  (`docker export` or a tar of the layer), mounted volumes.
- **NAS appliances.** Live: UAC over SSH plus SMB/NFS via dfnet and dfcollect.
  Off: image members, reconstruct from images (§3.1).

### 3.4 Mail

- **IMAP** (on-premises servers, hosters, freemail providers with credentials):
  `dfcollect mail` with its own IMAP client.
  - Only `EXAMINE`, never `SELECT`; `UID FETCH (BODY.PEEK[] FLAGS INTERNALDATE
    RFC822.SIZE)`, so `\Seen` and other flags never change.
  - Records `UIDVALIDITY` and UID per message, the TLS certificate chain and
    `CAPABILITY`.
  - Scope before any body is transferred: after `EXAMINE`, fetch only
    `UID FLAGS INTERNALDATE RFC822.SIZE` for `1:*`, filter `INTERNALDATE`
    against the exact UTC window of the scope, count what is skipped, then fetch
    matching bodies in bounded batches. (`SEARCH SINCE/BEFORE` is day-granular
    and ignores time zones; use it only as a coarse pre-filter for huge
    mailboxes.)
  - Output: one `.eml` per message (exact bytes) in a folder tree, plus a
    manifest with folder, UID, flags, internal date, size, SHA-256. Resumable.
  - Generic sync tools are unsafe for this: mbsync syncs both ways by default,
    imapsync and offlineimap are migration/sync tools. Keep them out of the
    procedure unless a test proves a configuration safe.
- **Microsoft 365.** Exchange Web Services is being switched off in Exchange
  Online (phased from 1 October 2026, gone on 1 April 2027), so EWS-based tools
  break now. On-premises Exchange Server keeps EWS. Use Microsoft Graph:
  - primary: messages as original MIME (`/messages/{id}/$value`) → `.eml`, plus
    the Graph message metadata as JSON, same manifest as IMAP; calendar and
    contacts as ICS/VCF;
  - optional: the mailbox export API (`exportItems`, generally available since
    May 2026) for full-fidelity preservation. It needs Exchange admin
    permission, takes 20 items per request and returns an opaque stream that no
    suite parses; it can only be re-imported into Exchange. Archive mailboxes
    via Graph are rolling out from late October 2026;
  - IMAP with OAuth (`XOAUTH2`) still works where Graph isn't possible.
  - With the tenant's cooperation: Purview eDiscovery export and the Unified
    Audit Log. The open Microsoft-Extractor-Suite (PowerShell, runs under `pwsh`
    on dfnix) covers UAL, sign-in logs, message trace and mailbox audit. Retention
    is short; logs first. Later `dfcollect` queries these logs through Graph
    itself, so the procedure no longer needs a PowerShell module.
- **Google.** Gmail API `format=raw`; Vault export with a Workspace admin.
- **POP3.** `RETR` without `DELE`. Rare.
- **Local stores** (PST/OST, mbox, Maildir, Thunderbird, Apple Mail): files,
  acquired by `dfcollect files` or the disk image. `libpff` (in nixpkgs) to
  check that a PST/OST is intact.
- **Tipping off.** Logging into an account can send "new sign-in" mails to the
  owner. The playbook says so; provider orders are the quiet route.

### 3.5 Files on servers and services

- **Mounted filesystems and shares.** `dfcollect files` reads from dfmount
  evidence mounts (`/media/evidence/...`) and dfnet share mounts. dfnet mounts
  shares under `/media/target/{smb,nfs}_*` today; move them to
  `/media/evidence/` so `/media/target` holds only writable destinations.
  Per-file manifest (path, size, all
  timestamps incl. birth time, owner/ACL, xattrs, symlink target, SHA-256,
  status `acquired | out_of_scope | read_error`), scope by path and date,
  and records the server's atime behaviour instead of assuming it.
- **Cloud and remote services** (OneDrive, SharePoint, Google Drive, Dropbox,
  Nextcloud/WebDAV, S3, SFTP, Box): `dfcollect cloud` drives **rclone** (MIT,
  70+ backends) and never writes to the remote:
  - read-only OAuth scopes where the provider has them (Drive `drive.readonly`);
  - listing before and after (`rclone lsjson`), so changes during the
    acquisition are visible;
  - provider-side hashes (OneDrive QuickXorHash, Drive MD5, Dropbox content hash,
    S3 ETag where meaningful) compared with the local SHA-256;
  - versions, trash and shared-with-me as explicit choices; the export format of
    Google-native documents recorded;
  - remote timestamps preserved and recorded.

### 3.6 Databases and business software

A logical dump shows the current state only. Deleted rows survive in data files
and in WAL, binlog or redo logs. Where possible take both: a consistent logical
dump and a file-level copy of data files and logs (from a filesystem snapshot or
the disk image). Copying a live data directory alone gives torn pages.

| Database | Consistent acquisition |
| --- | --- |
| PostgreSQL | `pg_dump --format=custom` (one snapshot; `--serializable-deferrable` optional) + `pg_dumpall --globals-only`; physical: `pg_basebackup --wal-method=stream` (footprint: forces a server checkpoint) |
| MySQL / MariaDB | `mariadb-dump --single-transaction --routines --triggers --events --hex-blob` (no locks for InnoDB); binlog coordinates with `--master-data=2` (MySQL 8: `--source-data=2`; footprint: brief `FLUSH TABLES WITH READ LOCK`); the binlogs themselves |
| MS SQL Server | `BACKUP DATABASE ... WITH COPY_ONLY` (keeps the backup chain intact) to a share the SQL service account can reach or a local path, then pulled and hashed; footprint: the file write and a backup-history row in `msdb` |
| MongoDB | `mongodump --oplog --archive` |
| SQLite | offline: the database together with `-wal` and `-shm`, never opening the original; live: raw copy of all three first, then optionally `sqlite3 .backup` for a consistent copy |

`dfcollect db` records server version, server clock, timezone and collation,
users and roles, schema, active sessions, the exact commands, and hashes.
Clients go into dfnix (postgresql, mariadb, sqlcmd, mongodb-tools are in nixpkgs).

German business software: the GoBD/GDPdU tax-audit export (`index.xml` + CSV,
"Beschreibungsstandard") is a standardised, verifiable export that accounting
systems must provide; `dfcollect` can verify and record such an export.

### 3.7 Cloud infrastructure (IaaS)

- Control-plane logs first, for the case time window: AWS CloudTrail, Azure
  Activity and Entra sign-in logs, GCP Cloud Audit Logs.
- Disks by snapshot: snapshot, copy into an evidence account, image from a
  forensic VM or download, hash. Google's libcloudforensics (Apache-2.0)
  automates this for AWS, Azure and GCP. Buckets via `dfcollect cloud` with
  version IDs.
- CLIs (awscli2, azure-cli, google-cloud-sdk) are large: a separate profile or
  the workstation/appliance images, not the default ISO.

### 3.8 Network traffic at the scene

`dfnet pcap` wraps dumpcap: pcapng, ring buffer with a SHA-256 per file,
capture filter, interface and offload settings (GRO/LRO/TSO change framing),
kernel drop counters (non-zero marks the capture incomplete), report and audit
record. Lawful interception (§ 100a StPO) runs on other systems and is out of
scope.

### 3.9 Provider deliveries (e-Evidence)

Regulation (EU) 2023/1543 applies since 18 August 2026 (German implementing act:
EBewMG). Providers deliver data packages. A small ingest step (`dfcollect
ingest`) verifies the provider's hashes, records receipt (who, when, channel),
stores the package read-only and adds it to the case manifest.

---

## 4. Requirements every acquisition path meets

1. **Read-only by the protocol's own means.** `EXAMINE` + `BODY.PEEK`, read-only
   scopes, `ro` mounts and mappings, snapshots, `COPY_ONLY`. Where no such
   primitive exists, the footprint is recorded.
2. **Hashes.** SHA-256 always; MD5/SHA-1 on request for hash databases and older
   suites. Hash at the source where possible, verify at the destination.
3. **One manifest format (dfcore).** Case, examiner, legal-basis reference,
   source identity, method, tool version and build revision, scope, start and
   end with clock reference, per-item and total hashes, errors, footprint.
   JSONL for tools and CSV for court annexes and X-Ways/Excel. Each manifest is
   anchored in the audit log. CASE/UCO (JSON-LD) export can follow for exchange.
4. **Scope (`ScopeSpec`).** Accounts, folders, paths, date window, legal-basis
   reference; enforced before bytes are written; out-of-scope items counted, not
   copied. The examiner and the warrant decide the scope; the tools record it.
5. **Footprint.** Protocol and command log: remote address, TLS version and
   certificate fingerprint, authentication method (never the secret), commands
   and queries, bytes sent and received; for dflive also processes, files and
   drivers it created.
6. **Time.** dfnix runs without NTP. Every report records the dfnix clock, the
   examiner's reference time, and the source's clock (suspect OS, SMB server,
   IMAP/HTTP `Date`, SQL `now()`) with the computed offset.
7. **Audit log off the live system.** `/run/dfnix/audit.jsonl` lives in RAM on
   the live ISO. `dfcore::audit::export` (CLI: `dfcore-audit export`) copies it
   into a case directory, and dfdisk already calls it after every acquisition.
   dfcollect and `dfnet receive` do the same; dfmount refreshes the copy on a
   target drive right before unmounting it, so later actions are kept too.
8. **Signing and timestamps (later).** Optional Ed25519 signatures on reports
   (minisign-compatible) and RFC 3161 timestamp requests (`.tsq`) generated
   offline, to be stamped once a network is available.
9. **Output the suites can read.** The target is the current releases of
   X-Ways and AXIOM (§9.2), which read the common formats. Physical: E01 and
   raw. VMs: native VMDK/VHDX/qcow2 plus memory files. Mail: `.eml` tree.
   Logical files: ZIP64 with the NTFS timestamp field (modified, accessed and
   created, at 100 ns), plus the manifest. The manifest also holds what ZIP
   can't: the inode change time, xattrs and ACLs. PAX tar is the alternative. Before
   the container is fixed, a short check confirms that the current releases
   open it and show the original timestamps; the check is repeated on major
   releases. The manifest stays the authoritative record either way.
10. **Tests prove it.** Each path gets a nixosTest like CFTT against a real
    service: Dovecot (flags and `\Seen` unchanged, every message hashed),
    PostgreSQL and MariaDB (dump consistent under concurrent writes), Samba and
    NFS (no writes, atime behaviour recorded), MinIO/S3 and a WebDAV server,
    md-RAID/LVM/ZFS (member images unchanged after assembly), dflive ↔ dfnet
    (authentication, unknown length, resume, hash). Windows and macOS paths get
    a written validation protocol until VM-based tests are practical.

---

## 5. Changes per repository

**dfnix**
- Packages (§7), ZFS in the kernel, libyal tools in `pkgs/`.
- Field-kit image: `nix build .#fieldkit` builds the stick of §3.2, one
  partition per OS. It holds dflive, AVML, UAC with a static busybox, a
  Velociraptor offline collector generated from a pinned spec, WinPmem, Fuji
  and the checklists. Everything is built from source except WinPmem and
  Fuji, which are pinned by hash. Manifests per partition and for the whole
  kit; every output records the kit's hash.
- Headless/server mode, BMC virtual-media validation, read-only iSCSI export,
  netboot artifact.
- Playbooks in `dfnix-guide` and docs.

**dfcore**
- Manifest and `ScopeSpec` types; audit actions: `volume_unlock`,
  `raid_assemble`, `logical_collection`, `mail_acquisition`, `cloud_acquisition`,
  `db_acquisition`, `pcap_capture`, `stream_receive`; later signing and `.tsq`.

**dfdisk**
- Opal locking state in reports; imaging of devices opened by `dfmount unlock`,
  with the physical identity recorded (via sysfs `slaves/`, or
  `/run/dfnix/unlocked.json` for the loop fallback).

**dfmount**
- `dfmount assemble` (md, LVM, ZFS, btrfs; from images preferred);
  `dfmount unlock` (LUKS, BitLocker, VeraCrypt, FileVault 2 via cryptsetup;
  Opal), with registry check and audit; refresh the audit copy before
  unmounting a target.

**dfnet**
- `receive` v2:
  - authenticated: a pairing code shown on dfnix and typed into dflive, giving
    TLS with a pre-shared key or a pinned one-time certificate;
  - streams of unknown length, closed by an authenticated trailer carrying the
    sender's byte count and SHA-256;
  - several streams per session; raw and file streams are resumable;
  - optional E01 on the fly via `ewfacquirestream`, not resumable.
    `ewfacquirestream` finalises a valid, `ewfverify`-clean E01 on any end of
    input, so a dropped connection yields a truncated image that verifies.
    dfnet must therefore rename it and record it as incomplete unless the
    sender's trailer arrived and matches.
- `pcap` (§3.8).
- Share mounts move from `/media/target/` to `/media/evidence/`.

**dfcollect** (new repository): `files`, `verify`, `mail`, `cloud`, `db`,
`ingest`.

**dflive** (new repository): `status`, `keys`, `mem`, `state`, `send` for the
suspect system. `dfkit` (write and verify kit sticks) is a separate Linux-only
crate in the same workspace. It uses dfcore and runs on dfnix only, so dfcore
never enters the Windows and macOS builds. Static builds: Nix cross-compiles the Windows (mingw) and Linux (musl)
binaries. macOS binaries come from a macOS build runner, because nixpkgs can't
cross-compile to macOS from Linux in practice.

---

## 6. Phases

Effort figures are rough, for one developer working with agents.

### P0: weeks, little new code
1. Packages from §7 that are in nixpkgs; ZFS with its lockdown; `vmd` and
   HBA drivers in the initrd.
2. Field kit v0: the multi-partition stick image (§3.2) with AVML, UAC,
   WinPmem, Fuji, the Velociraptor collector (built from source) and one-page
   checklists that also cover key capture with the built-in tools
   (`manage-bde`, `fdesetup`). It is written with `dd` and checked against its
   manifest until `dfkit` exists. Examiners get a running-system answer before
   dflive exists.
3. Playbooks: running Windows/macOS/Linux, Macs, servers and RAID, VMs,
   mailboxes, cloud; each with order, footprint and tipping-off warnings.
4. Documented "reconstruct from images" procedure; dfmount's RAID refusal
   points to it.
5. Check the logical container (ZIP64, §4.9) against the current X-Ways and
   AXIOM releases.

### P1: the core (a few months)
1. dfcore manifest + `ScopeSpec` + new audit actions.
2. `dfcollect files` + `verify` (+ nixosTests: Samba, NFS, local mounts).
3. `dfcollect mail`: IMAP first, then Microsoft Graph and Gmail
   (+ nixosTest with Dovecot).
4. dfnet `receive` v2 + `dflive` for Windows and Linux (`status`, `keys`,
   `mem`, `state`, `send`) + `dfkit`.
5. `dfmount unlock` and `dfmount assemble` (+ nixosTests with md/LVM/ZFS images).

### P2: breadth
1. `dfcollect cloud` (rclone; nixosTests with MinIO and WebDAV) and
   `dfcollect db` (nixosTests with PostgreSQL, MariaDB).
2. Headless/server mode, read-only iSCSI export, BMC boot validation.
3. `dfnet pcap`.
4. dflive for macOS; Share Disk workflow tested end to end.

### P3: completeness
- Hypervisor and container helpers (govc, Proxmox/KVM, Hyper-V via dflive),
  IaaS via libcloudforensics, `dfcollect ingest`, libyal packaging, netboot,
  report signing and RFC 3161, CASE/UCO export.

---

## 7. Packages for dfnix

| Package | Purpose | Licence | nixpkgs (pinned rev) |
| --- | --- | --- | --- |
| `avml` | Linux memory (kit and dflive; `pkgsStatic.avml` on the kit) | MIT | yes, 0.20.0 |
| `acquire`, `python3Packages.dissect` (`-target`, `-vmfs`, `-volume`, `-hypervisor`) | cross-platform collection; VMFS/VMDK/VHDX from images | AGPL-3.0 | yes, acquire 3.22 |
| `mdadm` | read-only md assembly (md, Synology SHR, QNAP) | GPL-2.0 | yes, 4.6 |
| `zfs` | read-only pool import | CDDL | yes, 2.4.4 |
| `sedutil` | Opal state | GPL-3.0 | yes |
| `thin-provisioning-tools` | QNAP LVM thin | GPL-3.0 | yes, 1.3.2 |
| `libpff` | PST/OST integrity check | LGPL-3.0 | yes |
| `govc` | ESXi / vSphere | Apache-2.0 | yes, 0.55.1 |
| `postgresql`, `mariadb`, `sqlcmd`, `mongodb-tools` | database clients | various | yes |
| `powershell` + Microsoft-Extractor-Suite | M365 logs | MIT / check | pwsh yes, module to package |
| `age`, `minisign` | encrypt captured keys; sign reports | BSD / ISC | yes |
| `awscli2`, `azure-cli`, `google-cloud-sdk` | IaaS (cloud profile) | Apache-2.0 | yes |
| libcloudforensics | IaaS disk copies | Apache-2.0 | no: package |
| `targetcli-fb` (LIO; NixOS iSCSI target module) | read-only iSCSI export | Apache-2.0 | yes |
| libvshadow, libfvde, libluksde, libvmdk, libvhdi | VSS, FileVault, LUKS, VM disks | LGPL-3.0 | no: package |
| `hfsprogs`, `exfatprogs`, `ntfs3g`, `gptfdisk` | build and write the field-kit stick | GPL-2.0 / various | yes |
| `pkgsStatic.busybox` | trusted userland for UAC on the kit | GPL-2.0 | yes, 1.37.0 |
| Velociraptor | Windows artifact collection (offline collector) | AGPL-3.0 | no: package from source (Go; the `bare` build without the web GUI suffices) |
| UAC | Unix artifact collection | Apache-2.0 | no: package from source (shell) |
| WinPmem | Windows memory | Apache-2.0 | no: pinned upstream release (driver signed by Microsoft) |
| Fuji | Mac logical acquisition | GPL-3.0 | no: pinned upstream `Fuji.dmg` (macOS app) |

Proprietary tools are out of scope (§9.4). No procedure depends on FTK Imager,
KAPE, DumpIt, Magnet RAM Capture or vendor RAID CLIs, and the kit has no slot
for them. Where open source has no answer (memory of Apple silicon Macs, some
hardware RAID layouts), the playbook names the gap.

---

## 8. Risks

- **Secure Boot and unbootable hardware** (Apple silicon, locked-down laptops):
  the live path and Share Disk are the answer; IDEAS.md tracks Secure Boot.
- **EDR and antivirus** on suspect systems may block or quarantine unsigned
  binaries or the WinPmem driver (HVCI, driver blocklist), and can alert a
  company's SOC. dflive keeps key capture and volatile state independent of the
  memory driver, so they succeed even if the driver is refused. Smart App
  Control and allowlisting policies (App Control for Business, AppLocker) may
  refuse an unsigned dflive.exe (§9.3); the checklists then fall back to the
  built-in tools for key capture.
- **Windows on Arm.** Memory capture on arm64 Windows laptops is unproven;
  check WinPmem's arm64 support before promising it.
- **Mutating the source** (IMAP flags, RAID resync, LVM metadata, DB locks,
  hypervisor snapshots): read-only primitives in code, proven by the nixosTests
  in §4.10; unavoidable changes are recorded.
- **Legal scope.** Remote and cloud access needs a per-case decision. The tools
  record scope and legal basis but never decide.
- **API churn.** EWS shutdown, Graph throttling, OAuth app consent in foreign
  tenants, MFA, provider-specific quirks.
- **Validation effort.** Every new path needs tests; Windows and macOS can't run
  in nixosTest easily.
- **Scope creep into analysis.** Outputs stay standard containers plus
  manifests; parsing and review stay in the analysis suites.

---

## 9. Maintainer decisions (2026-10-16)

1. **Case types.** Every kind of evidence above is common and will stay so. No
   source is dropped. P1 follows dependencies (manifest and scope first), not
   case types.
2. **Analysis suites.** Results must load in the current releases of X-Ways and
   AXIOM, which read the common formats. The format check in P0 and on their
   major releases covers this (§4.9).
3. **Code signing (open).** Signing puts a publisher signature into dflive.exe
   that Windows checks against trusted certificate authorities.
   - Run from the kit stick, the binary carries no Mark-of-the-Web, so
     SmartScreen doesn't intervene.
   - Smart App Control (Windows 11) and corporate allowlisting can refuse
     unsigned programs. EDR products also flag unsigned raw-disk and memory
     tools more readily.
   - A certificate costs a few hundred euros a year. It is issued to a legal
     entity, and its private key must sit on a hardware token or a cloud
     signing service. The signer's name then appears on the suspect system and
     in a company SOC's telemetry.
   - Kernel drivers need Microsoft's own signature. This is why WinPmem's
     upstream driver is used as-is.
   - On macOS, the ad-hoc signature from the build suffices for command-line
     tools started from the stick. A Developer ID signature with notarisation
     matters for app bundles and managed Macs.
   - Integrity doesn't depend on signing: the kit manifest and dflive's
     self-hash prove which binary ran.

   Not needed for P0 or P1. It is decided once dflive meets managed machines
   in practice, including who would sign.
4. **Proprietary tools** are out of scope. The df-suite should do as much as
   possible itself; see §2 and §7.
5. **Field kit** on its own stick, one partition per OS, rewritten for every
   case (§3.2).
