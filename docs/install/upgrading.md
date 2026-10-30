# Upgrading

- **Docker:** `docker compose pull && docker compose up -d`.
- **From source:** `git pull && bundle install && bin/rails assets:precompile db:prepare`, then restart.
- **Kamal:** `bin/kamal deploy`.

Migrations run on start with Docker (the image's entrypoint) and the systemd unit (`ExecStartPre`). If you start a bare `bin/rails server`, run `bin/rails db:prepare` first. Keep `storage/hideout-secrets.yml`: if it is lost on an install that has users, Hideout refuses to start rather than generate new keys that cannot read your data.

## From R2_* settings (raider_saas 9c)

Production no longer reads `secret_key_base` from `config/credentials.yml.enc`. Before upgrading an install that used it, set `SECRET_KEY_BASE` to the old value (`bin/rails credentials:show`). Otherwise Hideout generates a new one, finds existing users, and refuses to start.

Rename `ACTIVE_STORAGE_SERVICE=r2` → `s3`, `R2_ENDPOINT` → `S3_ENDPOINT`, `R2_BUCKET` → `S3_BUCKET`, `R2_ACCESS_KEY_ID` → `S3_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` → `S3_SECRET_ACCESS_KEY`, `BACKUP_ACCESS_KEY_ID` → `BACKUP_S3_ACCESS_KEY_ID`, `BACKUP_SECRET_ACCESS_KEY` → `BACKUP_S3_SECRET_ACCESS_KEY`, and add `S3_FORCE_PATH_STYLE=true`. The old names work for one more release and log a deprecation warning at boot.
