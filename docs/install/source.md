# Install from source

For a VM or a server you manage, without Docker.

## Requirements

- Linux or macOS, a C toolchain (`build-essential` on Debian/Ubuntu), `libyaml-dev`, `libvips`, `sqlite3`.
- Ruby 4.0.5. Most distributions don't package it yet; install it with [mise](https://mise.jdx.dev) (`mise use -g ruby@4.0.5`) or rbenv.
- Optional: `libpq-dev` for Postgres.

## Steps

    git clone https://github.com/RaiderHQ/ruby_hideout.git /opt/hideout
    cd /opt/hideout
    bundle config set --local without "development test postgres"   # drop "postgres" to use Postgres
    bundle install
    export RAILS_ENV=production APP_HOST=hideout.example.com SOLID_QUEUE_IN_PUMA=1
    SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
    bin/rails db:prepare
    bin/rails server

The first boot writes `storage/hideout-secrets.yml` (back it up with your database) and prints a setup link:

    [hideout] no users yet: open https://hideout.example.com/setup?code=ABCD-2345 to create the first admin

Open it to create the first admin, organization and project, or create them from the shell:

    bin/rails hideout:setup EMAIL=you@example.com ORG="Acme QA" PROJECT="Checkout web"

Both print the `RAIDER_ENDPOINT` and `RAIDER_TOKEN` values for your CI.

## Run it as a service

`deploy/systemd/hideout.service` runs the server as user `hideout` from `/opt/hideout`, reading settings from `/etc/hideout.env` (one `NAME=value` per line, see [configuration](configuration.md)). Put a TLS proxy in front: `deploy/proxy/Caddyfile` (automatic certificates) or `deploy/proxy/nginx.conf`.

On a trusted network without HTTPS, set `HIDEOUT_FORCE_SSL=false`.
