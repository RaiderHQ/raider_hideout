# Contributing to Raider Hideout

Thanks for helping. Bug reports, fixes, docs and features are all welcome.

## Reporting bugs and asking for features

Open an issue with what you did, what you expected and what happened instead. Include the Hideout version (the image tag or commit), how you installed it (source, Docker or Kamal) and the database (SQLite or Postgres).

Security problems go through [SECURITY.md](SECURITY.md), not public issues.

## Setting up

You need Ruby 4.0.5 (see `.ruby-version`), SQLite and libvips. Postgres is optional.

    bundle install
    bin/rails db:prepare
    bin/dev

Open http://localhost:3000. The first boot prints a `/setup` link with a one-time code; follow it to create the first admin.

## Before you open a pull request

Run what CI runs:

    bin/rails tailwindcss:build
    bundle exec rspec
    bin/rubocop
    bin/brakeman --no-pager
    bin/bundler-audit

If your change touches queries or migrations, also run the suite on Postgres (the test database is `hideout_test`):

    DB_ADAPTER=postgresql bin/rails db:test:prepare
    DB_ADAPTER=postgresql bundle exec rspec

Keep pull requests to one change, with specs for new behaviour. If you add or change a setting, update `docs/install/configuration.md`.

The client contract is shared with the [`raider_reporter`](https://github.com/RaiderHQ/raider_reporter) gem and the [Raider desktop app](https://github.com/RaiderHQ/raider_desktop): the `RAIDER_TOKEN` and `RAIDER_ENDPOINT` settings, the token formats and `/api/v1/*`. Changes there need to stay backwards compatible.

## License

Hideout is licensed under Apache-2.0. By submitting a contribution you agree that it is licensed under the same terms (section 5 of the [LICENSE](LICENSE)). No separate contributor agreement is needed.
