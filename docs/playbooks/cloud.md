# Cloud storage and cloud infrastructure

Cloud data has no disk you can take. You get it from the provider, from the
account, or, for infrastructure (IaaS), from snapshots and logs.

## 1. Choose the route

1. **The provider delivers.** A production order, or since 18 August 2026 a
   European Production Order (Regulation (EU) 2023/1543; German implementing
   act EBewMG). This is quiet and complete, including deleted items the provider
   still keeps. Check the provider's hashes on receipt and record who delivered
   it, when, and over which channel: `dfcollect ingest` stores the package
   with its receipt and checks every file against the provider's hash lists.
2. **The organisation cooperates** (Microsoft 365, Google Workspace, AWS,
   Azure, GCP): the tenant's admin exports or grants you read access, with
   their audit logs.
3. **Access with the account holder's credentials or sign-in.** This can tip
   them off ("new sign-in", "new app has access", connected devices).

Before you read anything, ask for **preservation**. Get the control-plane and
audit logs for the case's time window first, because they expire sooner than the
data.

## 2. Drives (OneDrive, SharePoint, Google Drive, Dropbox, Nextcloud/WebDAV, S3, SFTP, Box)

Use `dfcollect cloud`. It drives rclone, and rclone never writes to the
remote here.

- **Read-only access where the provider has it**, when you configure the
  remote (`rclone config`, into a file on the target):
  - Google Drive: `scope = drive.readonly`.
  - OneDrive/SharePoint: `access_scopes = Files.Read Files.Read.All
    Sites.Read.All offline_access`.
  - S3: credentials with read-only policies.
  - Elsewhere: an account or app password that can only read, if there is one.

```sh
dfcollect cloud evidence-drive:Projects --rclone-config /media/target/case01/rclone.conf \
  -o /media/target/case01/drive -C CASE -E cloud01 -e Examiner \
  --not-before 2026-01-01T00:00:00+01:00 --not-after 2026-07-01T00:00:00+02:00
```

What it does, so you don't have to:
- **Only reads.** It runs only `rclone lsjson` and `rclone cat` against the
  remote.
- **Listings and changes.** It lists the remote with the provider's hashes and
  IDs before and after, and records what changed in between.
- **Scope first.** It decides the scope (path, modification time) before
  reading anything.
- **Checked copies.** It streams every file into the container and checks it
  against the provider's own hash: MD5, SHA-1, SHA-256, OneDrive's
  QuickXorHash, Dropbox's content hash.
- **No secrets in the record.** It records rclone's version and the remote's
  configuration, with tokens and secrets removed.

Never use rclone's writing commands on the remote (`sync`, `move`, `bisync`,
`delete`, `purge`, `dedupe`, `cleanup`, `mkdir`/`rmdir`, `mount` with a write
cache).

Things to decide and write down:
- **Google-native documents** (Docs, Sheets, Slides) have no file to copy;
  they are exported. Choose the formats with
  `--rclone-arg=--drive-export-formats=docx,xlsx,pptx,pdf`; dfcollect records
  every extra rclone option.
- **Versions and trash:** say whether you take them (`--drive-trashed-only`
  for Drive's trash; OneDrive versions need the provider or the tenant).
- **Shared with me:** items others shared are a separate question of scope
  (`--drive-shared-with-me`).
- **The provider's hashes:** OneDrive's QuickXorHash, Drive's MD5, Dropbox's
  content hash, S3's ETag (not a plain MD5 for multipart uploads). Record them
  next to your SHA-256.

## 3. Mail in the cloud

See `mailboxes.md` (IMAP, Microsoft 365 with `dfcollect graph`, Google).

## 4. Cloud infrastructure (IaaS: AWS, Azure, GCP)

1. **Control-plane logs first**, for the case's time window:
   - AWS: CloudTrail;
   - Azure: the Activity Log and Entra sign-in logs;
   - GCP: Cloud Audit Logs.

   Also the flow logs and the load-balancer logs, if enabled.
2. **Disks by snapshot:** snapshot the VM's disks. Copy or share the
   snapshot into an evidence account you control. Then create a volume from it
   and image it from a forensic VM there (dfnix, or dfdisk on any Linux), or
   download it. Hash it. Google's libcloudforensics automates this for all
   three clouds.
3. **Memory:** only from inside the running VM (`live-linux.md`,
   `live-windows.md`, streamed with `dflive send`), or with the hypervisor
   provider's own tools where they exist.
4. **Buckets and object storage:** as in section 2, with version ids
   (`rclone lsjson --s3-versions` for S3).
5. The CLIs (awscli2, azure-cli, google-cloud-sdk) are large and not on the
   ISO. Use a workstation or appliance image with them, or the provider's cloud
   shell under the evidence account.

## Record

The route and its legal basis; the account or role you used and its
permissions. The commands with their logs, the listings before and after,
both kinds of hashes, and every snapshot or copy you created in the provider's
account (and whether you removed it).
