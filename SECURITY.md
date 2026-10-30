# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Don't open a public issue.

Include the Hideout version, how it is installed, and steps to reproduce. We aim to reply within a week and will tell you when a fix is released.

## Supported versions

Fixes go into the latest release. Self-hosted installs should upgrade to it (see [upgrading](docs/install/upgrading.md)).

## Running Hideout safely

- Keep HTTPS on (`HIDEOUT_FORCE_SSL`, default `true`) and put Hideout behind a TLS proxy.
- Back up `storage/hideout-secrets.yml` with the database; it holds `SECRET_KEY_BASE` (signs sessions) and the keys that encrypt stored secrets. Without it, Hideout can't use a restored database.
- Leave sign-up invite-only (`HIDEOUT_OPEN_SIGNUP=false`) unless the server is on a trusted network.

Every setting is described in [configuration](docs/install/configuration.md).
