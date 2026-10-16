# Cloud storage and cloud infrastructure

Cloud data has no disk you can take. You get it from the provider, from the
account, or, for infrastructure (IaaS), from snapshots and logs.

## 1. Choose the route

1. **The provider delivers.** A production order, or since 18 August 2026 a
   European Production Order (Regulation (EU) 2023/1543; German implementing
   act EBewMG). This is quiet and complete, including deleted items the provider
   still keeps. Check the provider's hashes on receipt and record who delivered
   it, when, and over which channel. `dfcollect ingest` for this is planned.
2. **The organisation cooperates** (Microsoft 365, Google Workspace, AWS,
   Azure, GCP): the tenant's admin exports or grants you read access, with
   their audit logs.
3. **Access with the account holder's credentials or sign-in.** This can tip
   them off ("new sign-in", "new app has access", connected devices).

Before you read anything, ask for **preservation**. Get the control-plane and
audit logs for the case's time window first, because they expire sooner than the
data.

## 2. Drives (OneDrive, SharePoint, Google Drive, Dropbox, Nextcloud/WebDAV, S3, SFTP, Box)

`dfcollect cloud` (rclone underneath, never writing to the remote) is planned.
Until then, use rclone on dfnix by hand, with the same rules:

- **Read-only access where the provider has it.**
  - Google Drive: `scope = drive.readonly`.
  - OneDrive/SharePoint: `access_scopes = Files.Read Files.Read.All
    Sites.Read.All offline_access`.
  - S3: credentials with read-only policies.
  - Elsewhere: an account or app password that can only read, if there is one.
- **Only commands that read the remote:** `lsjson`, `copy` (remote → local),
  `check`, `md5sum`/`sha1sum`/`hashsum`. Never `sync`, `move`, `bisync`,
  `delete`, `purge`, `dedupe`, `cleanup`, `mkdir`/`rmdir` on the remote, and no
  `mount` with a write cache.
- Run everything as one script and keep its log.

```sh
R=evidence-drive:            # the remote you configured
OUT=/media/target/case01/cloud
mkdir -p $OUT/files
# 1. What is there, with the provider's hashes and timestamps
rclone lsjson -R --hash --metadata --files-only $R > $OUT/listing-before.json
# 2. Copy (remote -> local only), keeping times and metadata
rclone copy $R $OUT/files --metadata --checksum --log-file $OUT/rclone.log --log-level INFO
# 3. Compare the provider's hashes with the copy
rclone check $R $OUT/files --one-way --log-file $OUT/check.log
# 4. What is there afterwards (changes during the acquisition show here)
rclone lsjson -R --hash --metadata --files-only $R > $OUT/listing-after.json
```

Then put the copy into a verifiable collection, with SHA-256 per file and a
manifest. The copy sits on the writable target, so dfcollect needs
`--allow-writable-source`, which it records:

```sh
dfcollect files $OUT/files -o $OUT/collection -C CASE -E cloud01 -e Examiner --allow-writable-source
```

Things to decide and write down:
- **Google-native documents** (Docs, Sheets, Slides) have no file to copy;
  they are exported. Record the format (`--drive-export-formats`, e.g.
  `docx,xlsx,pptx,pdf`).
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
