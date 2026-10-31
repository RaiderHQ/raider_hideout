# Install with Docker

    mkdir hideout && cd hideout
    curl -fsSLO https://raw.githubusercontent.com/RaiderHQ/ruby_hideout/main/deploy/docker/compose.yml
    curl -fsSL https://raw.githubusercontent.com/RaiderHQ/ruby_hideout/main/deploy/docker/.env.example -o .env
    # edit .env: at least APP_HOST, and HIDEOUT_VERSION to pin a release
    docker compose up -d
    docker compose logs web | grep setup

Open the printed `/setup?code=…` link, or run:

    docker compose exec web bin/rails hideout:setup EMAIL=you@example.com ORG="Acme QA" PROJECT="Checkout web"

Everything Hideout keeps (databases, attachments, nightly backups, `hideout-secrets.yml`) is in the `hideout_storage` volume. Back up the volume, or at least `storage/backups/` and `storage/hideout-secrets.yml`.

The image (`ghcr.io/raiderhq/hideout`) is built for amd64 and arm64 and listens on port 3000. The compose file publishes it on `127.0.0.1` only (`HIDEOUT_PORT` changes the port): put a TLS proxy on the same host in front (see `deploy/proxy/`). To reach it directly on a trusted network, remove `127.0.0.1:` from `ports` and set `HIDEOUT_FORCE_SSL=false`.

Postgres: uncomment the `db` service in `compose.yml` and follow the comment there.

The compose file runs `ghcr.io/raiderhq/hideout:${HIDEOUT_VERSION:-latest}`. Pin `HIDEOUT_VERSION` in `.env` to a release (recommended): `latest` follows every new release, pre-releases excluded.

Upgrading: change `HIDEOUT_VERSION` in `.env` (or leave it unset for `latest`), then `docker compose pull && docker compose up -d` (migrations run at start).
