# Raider Hideout

Self-hosted test reporting for [Ruby Raider](https://github.com/RaiderHQ/ruby_raider) projects. Your CI uploads results with the `raider_reporter` gem; Hideout groups them into builds and shows failures, flaky tests, error groups, analytics, quarantines and quality gates, and comments on pull requests.

Run it on your own machine: from source, with Docker, or with Kamal (see [Install](#install)).

## Install

- [From source](docs/install/source.md)
- [With Docker](docs/install/docker.md)
- [With Kamal](docs/install/kamal.md)

Every setting: [configuration](docs/install/configuration.md). Upgrades: [upgrading](docs/install/upgrading.md).

No email server? Invitations show a link to copy, and `bin/rails hideout:password_link EMAIL=you@example.com` prints a password reset link.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). To contribute, read [CONTRIBUTING](CONTRIBUTING.md); to report a vulnerability, [SECURITY](SECURITY.md).

## Production configuration

See [configuration](docs/install/configuration.md).

## Backups

`BackupJob` snapshots the primary SQLite database nightly at 02:30 server time (UTC in the Docker image) into `storage/backups/` (override with `BACKUP_DIR`). Each snapshot is integrity-checked before it is kept, so a failed check raises and leaves older backups alone. Files are `raider-YYYYMMDD-HHMMSS.sqlite3.gz` (UTC), mode 0600 in a 0700 directory. Run one by hand with `bin/rails backup:create`.

Keep rule: the 7 newest, plus the newest of each of the 4 most recent ISO weeks.

Restoring: `bin/rails backup:restore FILE=storage/backups/raider-YYYYMMDD-HHMMSS.sqlite3.gz`. This unpacks and checks the backup next to the live database as `<db>.restored` and never replaces the live database. Then follow the three printed steps (stop the app, move the file into place, start the app).

Not backed up: the cache, queue and cable databases (rebuilt on demand) and attachments (kept 30 days, kept in the storage volume or your S3 bucket).

Warnings:

* Backups share the database's disk until you set `BACKUP_BUCKET`; then each one is also copied offsite (see [configuration](docs/install/configuration.md#backups)).
* A restore needs the same secrets: keep `storage/hideout-secrets.yml` (or your `SECRET_KEY_BASE` and `ACTIVE_RECORD_ENCRYPTION_*` values) with your backups.

## Explore

`/projects/:id/explore` searches a project's tests (one row per test) or results (one row per result) on one branch over a time range (default 7 days, at most 90). The query box and the fields form edit the same filter:

| Syntax | Meaning |
|---|---|
| `login`, `"user signs in"` | words or phrases in the test name or file (Results: also error text) |
| `name:` `file:` `error:"Timeout"` | substring of the name, file path, or failure message and exception class |
| `status:failed,skipped` | latest status (Tests) or each result's status (Results) |
| `branch:main` `tag:smoke` `is:flaky` | branch (default: the project's default branch), all listed tags, flaky on the branch |
| `since:24h` `7d` `30d` `90d` | time range |
| `sort:failures` `recent` `duration` `name` | ordering |

Unknown filters and bad values are ignored with a notice. Saved views are personal unless shared; members and up can share, admins can edit or delete any shared view.

## Analytics

`/projects/:id/analytics` (the "Analytics" button on the project page) helps pick what to fix next. Every member of the project's organization can view it and export it, viewers included.

- **Filter:** one query box in Explore syntax with `branch:` (default: the project's default branch), `tag:` (repeat for all of), `file:` and `since:7d|30d|90d` (default 30d). Other terms are ignored with a notice.
- **Headline:** builds, average pass rate, average build duration and the newest build's flaky count over the window, each compared with the previous window of the same length. Build numbers follow `branch:` and `since:` only.
- **Lists (top 10 each):** most failing tests, slowest tests (by average duration), flakiest tests (current verdicts, by flip rate) and spec files (by failures). Quarantined results count as failures; skipped and pending results never count. Each list links to Explore with the same filter and to its CSV; clicking a spec file narrows the page to it.
- **Trends:** failure rate, average test and build duration, and flaky tests per day (7d, 30d) or per ISO week (90d). Empty days are gaps.
- **CSV:** `/projects/:id/analytics.csv?list=failing|slowest|flaky|files|trend&q=…`, at most 5,000 rows, cells that start with `=`, `+`, `-`, `@`, a tab or a carriage return prefixed with `'`.

Everything is computed live from stored results and builds, so test-level numbers reach back only as far as `RETENTION_RESULT_DAYS` (default 90); build numbers are kept forever.

## Quarantine

Members can quarantine a flaky test from its page or the flaky list, with a reason (up to 500 characters) and 7, 14 or 30 days; they can extend (from now) or release it, with an optional note. Viewers see the state, the history and `/projects/:id/quarantine` (active quarantines by expiry, and the 50 most recent changes). A quarantine applies on every branch and ends at its expiry; a nightly job (`ExpireQuarantinesJob`, 03:45) records the `expired` event. Changes are an insert-only trail.

raider_reporter 0.8.0+ fetches `GET /api/v1/quarantine` (project token; active quarantines as `{"quarantined":[{"test_key","expires_at"}]}`) when `RAIDER_QUARANTINE=1`, reports matching failures as `quarantined` in schema 2, and `raider-reporter exec -- <cmd>` keeps the CI build green when they are its only failures. Ingest accepts schema 1 and 2. Quarantined results are counted separately (`quarantined_count`), keep their failure details and error groups, never fail a run or build, count as not passing in pass rates (build, run and Explore Tests: passed / (passed + failed + quarantined)) and as failures for flakiness and Explore failure counts, and are searchable with `status:quarantined` and `is:quarantined`.

## Quality gates

Admins turn on gate rules on a project's Gate page (`/projects/:id/gate`): a minimum pass rate (passed ÷ (passed + failed); quarantined results never count), no new failures against the build's baseline on the default branch, and no new flaky tests. Every member role can view the page. When a build is ready (every shard in and analysed), `Builds::Gate` computes one verdict, `none`, `passed` or `failed`, and stores it on the build with the rule values used. It is never recomputed: late shards and later rule edits do not change it. A rule with nothing to compare against is skipped with a reason and does not fail; an evaluation error leaves the verdict pending. The build page shows a badge and a "Quality gate" panel, the builds list a gate column, and the PR comment a `**Gate:**` line.

raider_reporter 0.9.0+ `raider-reporter gate` polls `GET /api/v1/builds/gate?build_key=` (project token, 300 requests a minute; `{"state","build_state","shards","rules","url"}`, where `state` is `pending` until the verdict exists), exits 1 when the gate failed and 2 when it gets no verdict, and posts a `raider/gate` status. `GET /api/v1/builds/summary` also returns `"gate"`. Builds that existed before gates shipped have the verdict `none`. ruby_raider 3.9.0 projects can opt in to a CI gate job with the variable `RAIDER_GATE=1`.

## Public API and MCP

Any signed-in user creates personal tokens on the Tokens page (`/account/tokens`, in the navbar): read-only, prefixed `rdp_`, expiring after 30, 90 (default) or 365 days or never, at most 20 active per user. A token is shown once; Raider stores only its SHA-256 digest and its first 8 characters. Revoking keeps the row and stops the token at once. A token sees exactly the projects of its owner's organizations, checked on every request, so leaving an organization removes its projects immediately. Project (`rdr_`) tokens and personal tokens never work in each other's place.

The JSON API lives under `/api/v1/projects` (`Authorization: Bearer rdp_…`): projects, a project's 30-day health, builds and a build (by id or `latest`), Explore test search (`?q=`, Explore syntax; notices come back in `meta.notices`) and a test, error groups and a group, flaky tests and active quarantines. Lists take `page` and `per_page` (1–100, default 50). `docs/openapi.yaml` (OpenAPI 3.1, served at `/api/v1/openapi.json`) documents every endpoint, and every API request spec validates its response against it.

`POST /mcp` serves the same data to Claude and other MCP clients over stateless streamable HTTP, as ten tools (`list_projects`, `project_health`, `list_builds`, `get_build`, `search_tests`, `get_test`, `list_error_groups`, `get_error_group`, `list_flaky_tests`, `list_quarantines`), each returning a text summary plus the REST JSON. A personal token has 600 requests a minute, shared between the API and MCP.

```bash
claude mcp add --transport http raider https://APP_HOST/mcp --header "Authorization: Bearer rdp_…"

curl -s https://APP_HOST/mcp -H "Authorization: Bearer rdp_…" \
  -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}'
```

## Deploying

See [Install](#install). `bin/deploy-check` builds the image and checks it end to end against MinIO before you deploy. Before publishing, `bin/scan-secrets` checks the git history for secrets (gitleaks).

## Switching to Postgres

SQLite is the default. Setting `DB_ADAPTER=postgresql` moves the primary database to Postgres. The `pg` gem is in the `postgres` Bundler group: `bundle install` installs it (needs libpq), and `bundle config set --local without postgres` skips it. The Docker image includes it.

Check that the suite passes on Postgres:

```bash
DB_ADAPTER=postgresql RAILS_ENV=test bin/rails db:create db:schema:load && DB_ADAPTER=postgresql bundle exec rspec
```

Moving data:

1. Set `DB_ADAPTER=postgresql` and `DATABASE_URL`.
2. Run `bin/rails db:create db:schema:load`.
3. Stop writes (stop the app).
4. Copy every table in foreign-key order, keeping ids.
5. Reset each id sequence: `SELECT setval(pg_get_serial_sequence('<table>', 'id'), COALESCE(MAX(id), 1)) FROM <table>;`
6. Start the app.

The cache, queue and cable databases stay SQLite.
