# Mailboxes

Mail lives on servers. You reach it in one of three ways:

- a provider order, the quiet route: the provider exports it;
- the tenant's or admin's cooperation (Microsoft 365, Google Workspace);
- access with the account holder's credentials or sign-in.

Decide which before anything else: signing in to an account can tip off its
holder.

## 0. Before you sign in anywhere

- **Tipping off.** A sign-in from a new device or place can send the holder a
  "new sign-in" alert, by mail, push or SMS. Consent to an app can also send a
  "new app has access" alert. Where the investigation must stay covert, use a
  provider order or the tenant's cooperation, never the holder's account.
- **Logs first.** The logs that show who read, moved or deleted mail expire
  sooner than the mail. In Microsoft 365, sign-in logs are kept for 7–30 days,
  and the Unified Audit Log for 180 days or more, depending on the licence. Ask
  the tenant to export or preserve them before anything else, and before your
  own access adds entries.
- **Preservation.** Ask the provider or tenant to preserve the mailbox (a
  litigation or eDiscovery hold), so that nothing is deleted while you work.
- **Scope.** Write the time window and the folders into the scope from the
  order (`--not-before`, `--not-after`, `--include`, `--exclude`, or a scope
  file). dfcollect decides every message before fetching its body, and records
  what it left out.
- **Clock.** Note dfnix's clock against a reference
  (`--reference-time` with `--reference-how` on every dfcollect run).

## 1. IMAP (on-premises servers, hosting providers, freemail with credentials)

```sh
dfcollect imap mail.example.org --user anna@example.org --password-file /run/pw \
  -o /media/target/case01/anna-mail -C "CASE" -E mail01 -e "Examiner" \
  --legal-basis "order ..." --include "INBOX/**" --exclude "INBOX/Spam/**" \
  --not-before 2026-01-01T00:00:00+01:00 --not-after 2026-07-01T00:00:00+02:00
```

- Read-only by protocol: `EXAMINE` with `[READ-ONLY]` required, and
  `BODY.PEEK[]`. No flag changes, `\Seen` included.
- TLS is checked against the system CAs. For a server with an internal CA,
  compare its fingerprint on a trusted channel and pass `--tls-sha256`.
- For OAuth-only providers (Microsoft 365, Gmail over IMAP), use
  `--token-file` with `--auth xoauth2`. For Microsoft 365, Graph (below) is
  usually the better route.
- Never use sync tools (mbsync, imapsync, offlineimap): they sync both ways or
  migrate.

## 2. Microsoft 365 (Exchange Online)

Exchange Web Services is being switched off in Exchange Online, so EWS-based
tools stop working. Use Microsoft Graph with `dfcollect graph`. On-premises
Exchange Server keeps IMAP and EWS.

**Prepare once (your agency's tenant):** create an app registration. It gives
you the client id.
- For `--auth device`, allow public client flows and add the delegated
  permission `Mail.Read`.
- For `--auth app`, the suspect tenant's admin grants the application
  permission `Mail.Read` to your app. Ask them to restrict it to the mailboxes
  in the order with an application access policy.

**With the holder's sign-in (`--auth device`):**

```sh
dfcollect graph --client-id <app id> --tenant <tenant id or domain> \
  -o /media/target/case01/anna-m365 -C "CASE" -E mail02 -e "Examiner" \
  --legal-basis "order ..." --exclude "Junk Email/**" \
  --not-before 2026-01-01T00:00:00+01:00 --not-after 2026-07-01T00:00:00+02:00
```

dfcollect prints a code and microsoft.com/devicelogin. Sign in as the account on
any device with a browser and consent to Mail.Read. The token is renewed during
long runs.

**With the tenant's cooperation (`--auth app`):** add `--auth app --mailbox
anna@contoso.com --client-secret-file /run/secret`.

What dfcollect records and doesn't change:
- only GET requests reach Graph; `isRead` and every other property stay as
  they were;
- all folders, hidden ones too, and Recoverable Items (deletions). Purges and
  versions in Recoverable Items need an eDiscovery export by the tenant;
- each body is Exchange's MIME rendition of the stored item, not necessarily
  the bytes once received. The manifest says so, and every item carries Graph's
  metadata with the immutable id;
- the tenant's sign-in log records your sign-in, and Exchange may log
  MailItemsAccessed in the Unified Audit Log. Note that in the report.

National clouds: `--graph-endpoint` and `--login-endpoint` (US Government,
China).

**Logs (tenant cooperation):** the Unified Audit Log, sign-in logs and message
trace come from the tenant: Purview Audit export, or the admin runs
Microsoft-Extractor-Suite. dfcollect will read them through Graph itself later.

## 3. Google (Gmail, Workspace)

- With a Workspace admin: a Vault export (mbox per account) is the quiet,
  complete route.
- With the account: Gmail over IMAP with an OAuth token (`dfcollect imap
  imap.gmail.com --auth xoauth2 --token-file ...`). Gmail exposes labels as
  folders, so a message with several labels appears in several folders.
- `dfcollect gmail` (Gmail API, `format=raw`, labels recorded once per message)
  is being built.

## 4. POP3

Rare. `RETR` without `DELE`, and no client that "leaves mail on the server for
n days". dfcollect has no POP3 client; prefer IMAP when the server offers both.

## 5. Local stores (PST/OST, mbox, Maildir, Thunderbird, Apple Mail)

These are files: they come with the disk image, or from a mounted share with
`dfcollect files`. Check a PST or OST for damage before you rely on it:

```sh
pffinfo archive.pst              # header, encryption, item counts
pffexport -m all archive.pst     # export; recovered and orphan items too
```

An OST is a cache. Pull the mailbox itself from the server when the order
covers it.

## 6. Afterwards

- `dfcollect verify <collection>`: records, container members and audit
  anchors are re-checked.
- `data.zip` is a ZIP64 container of `.eml` files in a folder tree. X-Ways and
  AXIOM read it (see the ingest check in the roadmap). `items.jsonl` and
  `items.csv` carry each message's metadata and hashes.
- Write the route, the account used, the sign-in method and the expected
  footprint into the report.
