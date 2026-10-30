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
| `RETENTION_ATTACHMENT_DAYS` | `30` | Attachments older than this are deleted nightly. |
| `RETENTION_RESULT_DAYS` | `90` | Test results older than this are deleted; build totals stay. |

## Error tracking

| Variable | Default | What it does |
|---|---|---|
| `SENTRY_DSN` | — | Send errors to Sentry (personal data scrubbed). |
| `SENTRY_TRACES_SAMPLE_RATE` | `0` | Performance tracing sample rate. |

## Deprecated (one release)

`R2_ENDPOINT`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `BACKUP_ACCESS_KEY_ID`, `BACKUP_SECRET_ACCESS_KEY` and `ACTIVE_STORAGE_SERVICE=r2`: see [upgrading](upgrading.md).
