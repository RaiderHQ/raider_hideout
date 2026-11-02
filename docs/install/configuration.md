# Configuration

Every setting is an environment variable. Hideout checks them at boot and stops with one line naming each problem.

## Basics

| Variable | Default | Required | What it does |
|---|---|---|---|
| `APP_HOST` | — | yes | Host name (and `:port` if not 80/443) people and CI use. Used for links, `RAIDER_ENDPOINT` and host checks. |
| `ALLOWED_HOSTS` | — | no | Extra host names, comma-separated. |
| `HIDEOUT_FORCE_SSL` | `true` | no | Redirects plain HTTP to HTTPS and marks cookies secure. `false` serves plain HTTP (trusted networks only; boot warns). |
| `HIDEOUT_ASSUME_SSL` | `false` | no | `true` treats every request as HTTPS. Only for a TLS proxy that sends no `X-Forwarded-Proto` header (Caddy, nginx with the example config and kamal-proxy send it). |
| `HIDEOUT_OPEN_SIGNUP` | `false` | no | `true` lets anyone register. Needs `SMTP_ADDRESS`. |
| `HIDEOUT_SETUP_CODE` | random, in the boot log | no | Fixed first-run setup code (use it when Puma runs several workers). |
| `HIDEOUT_SECRETS_FILE` | `storage/hideout-secrets.yml` | no | Where generated secrets are kept. |
| `PORT` | `3000` | no | Port Puma listens on. |
| `HIDEOUT_PORT` | `3000` | no | Host port in `deploy/docker/compose.yml`. |
| `HIDEOUT_VERSION` | `latest` | no | Image tag `deploy/docker/compose.yml` runs. Pin a release (for example `1.0.0`) so `docker compose pull` only upgrades when you change it. |
| `SOLID_QUEUE_IN_PUMA` | — | recommended | `1` runs background jobs inside the web process. |
| `JOB_CONCURRENCY`, `WEB_CONCURRENCY`, `RAILS_MAX_THREADS` | Rails defaults | no | Process and thread counts. |
| `RAILS_LOG_LEVEL` | `info` | no | Log level. |

## Secrets

Generated on first boot into `HIDEOUT_SECRETS_FILE` unless set. Setting them as variables keeps them off the server's disk.

| Variable | What it protects |
|---|---|
| `SECRET_KEY_BASE` | Sessions and signed links. |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Encrypted columns (webhook URLs, invitation tokens). A restore needs the same values. |

## CI access

Re-running failed builds from Hideout needs a GitHub token per project. GitHub Actions only: no Azure, no GitHub Enterprise. The server must be able to reach `https://api.github.com`.

1. In GitHub, create a fine-grained personal access token for the repository with **Actions: Read and write** and **Metadata: Read**. A classic `ghp_` token also works, but it is broader than needed.
2. In Hideout, open the project, then CI access (admins and owners only), paste the token and save.
3. Press Test connection. It checks that GitHub accepts the token and can see the repository, using the project's latest GitHub Actions build. It cannot prove Actions: Read and write, so a first re-run may still be refused with a 403.

The token is stored encrypted (Active Record encryption, see Secrets above) and is never shown again. Replace it or remove it on the same page. Back it up with the database and `storage/hideout-secrets.yml`.

Members and above then see Re-run failed on failed GitHub Actions builds. It calls GitHub's re-run failed jobs endpoint, so only the failed jobs run again, never the whole workflow. After GitHub accepts a re-run, that attempt can't be re-run again from Hideout for 10 minutes. The build page lists who asked, when, and what GitHub answered. The result arrives as the next attempt on the same build, and the person who started the re-run gets a push for that attempt (not for later ones).

## Email (optional)

Without `SMTP_ADDRESS`, invitations show a link to copy, the forgot-password link is hidden (use `bin/rails hideout:password_link EMAIL=…`), and email notification channels are unavailable.

| Variable | Default | What it does |
|---|---|---|
| `SMTP_ADDRESS` | — | SMTP server. Turns email on. |
| `SMTP_PORT` | `587` | Port (STARTTLS). |
| `SMTP_USERNAME`, `SMTP_PASSWORD` | — | Login. |
| `MAILER_FROM` | `Raider Hideout <no-reply@localhost>` | Sender. Required when `SMTP_ADDRESS` is set. |

## Database

| Variable | Default | What it does |
|---|---|---|
| `DB_ADAPTER` | SQLite | `postgresql` moves the primary database to Postgres. |
| `DATABASE_URL` | — | Postgres connection URL. |

## Attachments

| Variable | Default | What it does |
|---|---|---|
| `ACTIVE_STORAGE_SERVICE` | `local` | `s3` stores screenshots and videos in any S3-compatible service. |
| `S3_ENDPOINT` | AWS | Endpoint URL for R2, MinIO, Backblaze… Empty means AWS. |
| `S3_REGION` | `auto` | Region. Required (a real AWS region) when `S3_ENDPOINT` is empty. |
| `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | — | Bucket and key pair. |
| `S3_FORCE_PATH_STYLE` | `false` | `true` for MinIO and other path-style services. |

## Backups

| Variable | Default | What it does |
|---|---|---|
| `BACKUP_DIR` | `storage/backups` | Where nightly snapshots go. |
| `BACKUP_BUCKET` | — | Also copy each snapshot offsite. |
| `BACKUP_S3_ENDPOINT`, `BACKUP_S3_REGION` | the attachment settings | Offsite endpoint and region. With no endpoint at all (AWS), a real region is required. |
| `BACKUP_S3_ACCESS_KEY_ID`, `BACKUP_S3_SECRET_ACCESS_KEY` | — | A separate key pair for backups. Required with `BACKUP_BUCKET`. |

## Retention

| Variable | Default | What it does |
|---|---|---|
| `RETENTION_ATTACHMENT_DAYS` | `30` | Attachments older than this are deleted nightly, including screenshot comparison images. |
| `RETENTION_RESULT_DAYS` | `90` | Test results older than this are deleted; build totals stay. Screenshot comparison records go with their result. |

## Error tracking

| Variable | Default | What it does |
|---|---|---|
| `SENTRY_DSN` | — | Send errors to Sentry (personal data scrubbed). |
| `SENTRY_TRACES_SAMPLE_RATE` | `0` | Performance tracing sample rate. |

## Phone notifications

| Variable | Default | What it does |
|---|---|---|
| `HIDEOUT_VAPID_PUBLIC_KEY`, `HIDEOUT_VAPID_PRIVATE_KEY` | generated, stored encrypted in the database | Your own VAPID pair. Set both or neither; one alone fails. While set, `hideout:vapid:rotate` refuses to run. Setting or changing these after devices subscribed means every device must turn notifications on again; until then sends fail as unauthorized and are only logged. |
| `HIDEOUT_VAPID_SUBJECT` | the owner's `mailto:` address, else the project URL | Contact sent to push services. |
| `HIDEOUT_PUSH_HOSTS` | — | Extra push hosts, comma-separated. Added to the default allowlist (`fcm.googleapis.com`, `*.push.apple.com`, `updates.push.services.mozilla.com`, `*.notify.windows.com`). |

Phones need HTTPS; see the README's Phone section.

## Deprecated (one release)

`R2_ENDPOINT`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `BACKUP_ACCESS_KEY_ID`, `BACKUP_SECRET_ACCESS_KEY` and `ACTIVE_STORAGE_SERVICE=r2`: see [upgrading](upgrading.md).
