# Install with Kamal

For deploys to your own servers with zero-downtime restarts.

1. Copy `deploy/kamal/deploy.yml.example` to `config/deploy.yml` and `deploy/kamal/secrets.example` to `.kamal/secrets`.
2. Export `KAMAL_REGISTRY_IMAGE` (e.g. `you/hideout`), `KAMAL_SERVER_IP`, `KAMAL_REGISTRY_USERNAME`, `KAMAL_REGISTRY_PASSWORD`, `APP_HOST`, and any optional settings (see [configuration](configuration.md)). The example passes every setting listed there; one you leave unset gets the app's default.
3. `bin/kamal setup`, then `bin/kamal app logs | grep setup` for the setup link, or `bin/kamal app exec 'bin/rails hideout:setup EMAIL=… ORG=… PROJECT=…'`.

kamal-proxy gets a Let's Encrypt certificate for `APP_HOST`. The example's comments show the Cloudflare origin-certificate option.

The `hideout_storage` volume holds the databases and `hideout-secrets.yml`; back it up. To keep the secrets outside the server instead, export `SECRET_KEY_BASE` and the three `ACTIVE_RECORD_ENCRYPTION_*` variables before deploying: they are already listed in `env.secret` and `.kamal/secrets`, and left unset they fall back to the generated file.

Postgres: export `DB_ADAPTER=postgresql` and `DATABASE_URL`, and uncomment the `DATABASE_URL` lines in `config/deploy.yml` (`env.secret`) and `.kamal/secrets`. They ship commented out because Kamal sends an unset secret as an empty value, and Rails refuses an empty `DATABASE_URL`.
