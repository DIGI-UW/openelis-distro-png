# OpenELIS Global: Papua New Guinea distribution

This repository is the deployment package for OpenELIS Global in Papua New
Guinea. It is a Docker Compose stack that brings up the full OpenELIS system
(database, web application, FHIR API, front end, HTTPS proxy and analyzer
bridge) with the PNG configuration already in place.

It is written for the National Department of Health ICT staff who install and
run OpenELIS servers. Developer and release notes are at the end.

- [What you need](#what-you-need)
- [Choosing a version](#choosing-a-version)
- [Installing a server](#installing-a-server)
- [Set the admin password (mandatory)](#set-the-admin-password-mandatory)
- [HTTPS with Let's Encrypt](#https-with-lets-encrypt)
- [Day-to-day operation](#day-to-day-operation)
- [Loading the PNG test catalog](#loading-the-png-test-catalog)
- [PNG configuration included](#png-configuration-included)
- [Analyzers](#analyzers)
- [For maintainers](#for-maintainers)

## What you need

| Item | Requirement |
|---|---|
| Operating system | Ubuntu Server LTS (22.04 or 24.04), 64-bit x86 (`amd64`) |
| CPU / memory | 4 cores and 8 GB RAM minimum |
| Disk | 50 GB free to start; plan for growth in results and backups |
| Software | Docker Engine with the Compose v2 plugin (`docker compose`), `git` |
| Network | Internet access during install to pull images; ports 80 and 443 reachable by users |
| Hostname | A DNS name for the server (for example `lab.health.gov.pg`) pointing at its public IP, for the Let's Encrypt certificate |
| Access | A user with `sudo` rights |

Check Docker is ready before you start:

```bash
docker --version
docker compose version
```

### Ports

The stack publishes these ports on the host. Only 80 and 443 need to be
reachable by lab users; firewall the rest.

| Port | Used by | Who needs it |
|---|---|---|
| 80, 443 | Web interface (HTTPS proxy); port 80 also answers Let's Encrypt checks | All users, and the internet for port 80 |
| 12000 | Analyzer bridge, ASTM listener | Analyzers on the lab network only |
| 8442 | Analyzer bridge API | Local only |
| 8080, 8443 | Web application (behind the proxy) | Local only |
| 8081, 8444 | FHIR API | Local only, or the consolidated server if connected |
| 15432 | PostgreSQL database | Local only |

## Choosing a version

Always install from a **release tag**, not from `main`. The `main` branch
follows the OpenELIS development build and changes every day; a tag is a
fixed, tested snapshot that installs the same way every time.

Find the current release on the
[Releases page](https://github.com/DIGI-UW/openelis-distro-png/releases), or
list tags from the command line:

```bash
git ls-remote --tags https://github.com/DIGI-UW/openelis-distro-png
```

In the commands below, replace `<release-tag>` with the tag you chose. Record
which tag each server runs; you need it for upgrades and rollbacks.

## Installing a server

### 1. Get the release

```bash
git clone --branch <release-tag> https://github.com/DIGI-UW/openelis-distro-png
cd openelis-distro-png
```

Each release also has a downloadable tarball on the Releases page if the
server cannot reach GitHub directly.

### 2. Set site passwords

```bash
cp .env.example .env
nano .env
```

Set these three values for every real site:

| Variable | What it is |
|---|---|
| `OE_DB_PASSWORD` | Database password for the OpenELIS schema |
| `ADMIN_PASSWORD` | PostgreSQL superuser password (used at first start) |
| `OE_ADMIN_PASSWORD` | Password for the OpenELIS `admin` login |

`OE_ADMIN_PASSWORD` must meet the OpenELIS password policy: at least 8
characters, only `A-Z a-z 0-9 _ % $ # !`, and at least three of lowercase,
uppercase, digit and special character. A hyphen (`-`), `@` or `*` will be
rejected.

`.env` holds passwords. Never commit it or copy it anywhere unprotected.

### 3. Prepare folders

```bash
./scripts/fix-config-permissions.sh
./scripts/init-bridge-state.sh
```

Run both before the first start. They are safe to run again at any time.
Skipping the first one makes OpenELIS log `Failed to save checksums file`
and reload the whole catalog on every start.

### 4. Start the stack

```bash
docker compose up -d
docker compose ps
```

Wait until `oe.openelis.org` shows `healthy`. The first start takes several
minutes while the database is created and the catalog is loaded.

### 5. Set the admin password

Run `./scripts/set-admin-password.sh`. See the next section; this step is
required.

### 6. Set up HTTPS

Follow [HTTPS with Let's Encrypt](#https-with-lets-encrypt) below. Until you
do, the server uses a self-signed certificate and browsers show a warning.

### 7. Log in

Open `https://<your-hostname>/` and sign in as `admin` with the password you
set.

## Set the admin password (mandatory)

Putting `OE_ADMIN_PASSWORD` in `.env` does **not** change the login password
on its own. Every new site starts with the published default
`admin` / `adminADMIN!` until you run:

```bash
./scripts/set-admin-password.sh
```

The script applies `OE_ADMIN_PASSWORD`, then confirms the new password works
and the default no longer does. Check a site at any time with:

```bash
./scripts/set-admin-password.sh --check
```

If you later change the admin password in the application
(Administration > Users), update `OE_ADMIN_PASSWORD` in `.env` to match. The
analyzer bridge signs in with it.

## HTTPS with Let's Encrypt

The Ministry uses Let's Encrypt for server certificates. The distro includes
an overlay (`compose.letsencrypt.yaml`) and a script
(`scripts/generate-letsencrypt-certs.sh`) that request, install and renew
the certificate. Full reference: [docs/letsencrypt.md](docs/letsencrypt.md).

### Before you start

- The hostname (for example `lab.health.gov.pg`) has a DNS `A` record
  pointing at this server's public IP address.
- **Port 80** is open to the internet. Let's Encrypt checks it to prove you
  control the hostname. Port 443 is open to users.
- The stack is running (`docker compose ps` shows the proxy up).

### 1. Add the Let's Encrypt settings to `.env`

Uncomment the `LETSENCRYPT_*` block in `.env` and fill it in, and add the
`COMPOSE_FILE` line so every `docker compose` command uses the overlay:

```dotenv
LETSENCRYPT_EMAIL=ict-team@health.gov.pg
LETSENCRYPT_DOMAINS=lab.health.gov.pg
LETSENCRYPT_PRIMARY_DOMAIN=lab.health.gov.pg
LETSENCRYPT_CERT_NAME=lab.health.gov.pg

COMPOSE_FILE=docker-compose.yml:compose.letsencrypt.yaml
```

Use a shared team mailbox for `LETSENCRYPT_EMAIL`; expiry warnings go there.
To put more than one name on the certificate, list them in
`LETSENCRYPT_DOMAINS` separated by commas.

The `COMPOSE_FILE` line matters. Without it, a later plain
`docker compose up -d` (for example during an upgrade) starts the proxy
without the overlay and it falls back to the self-signed certificate.

### 2. Test without using up the quota

```bash
./scripts/generate-letsencrypt-certs.sh --dry-run
```

Let's Encrypt limits how many real certificates a hostname can get per week.
The dry run checks DNS, port 80 and the settings without counting against
that limit. Fix any error before going on.

### 3. Request the certificate

```bash
./scripts/generate-letsencrypt-certs.sh
```

### 4. Switch the proxy to the new certificate

```bash
docker compose up -d --force-recreate proxy
```

### 5. Check it

```bash
curl -I http://lab.health.gov.pg        # should redirect to https
curl -v https://lab.health.gov.pg/ 2>&1 | grep -i "issuer\|expire"
```

In a browser the padlock should show a valid certificate with no warning.

### Renewal

Let's Encrypt certificates last 90 days. Run the same script regularly; it
renews only when the certificate is close to expiry, and does nothing
otherwise. Add a weekly job to root's crontab (`sudo crontab -e`), adjusting
the folder to where you cloned the distro:

```cron
0 3 * * 1 cd /opt/openelis-distro-png && ./scripts/generate-letsencrypt-certs.sh >> /var/log/oe-letsencrypt.log 2>&1 && docker compose restart proxy
```

The proxy restart makes nginx load a renewed certificate. It takes a few
seconds and is scheduled for 03:00 on Mondays to avoid working hours. Check
`/var/log/oe-letsencrypt.log` after the first run.

## Day-to-day operation

### Status and logs

```bash
docker compose ps                                # is everything running?
docker compose logs -f oe.openelis.org           # web application log
docker compose logs -f openelis-analyzer-bridge  # analyzer bridge log
```

### Stop and start

```bash
docker compose stop        # stop, keeping all data
docker compose up -d       # start again
```

Do not run `docker compose down -v`. The `-v` deletes volumes.

### Backups

```bash
sudo ./scripts/backup.sh                    # writes ./backups/<timestamp>/
sudo ./scripts/backup.sh /srv/oe-backups    # or to a folder you choose
```

It must run with `sudo`, or the backup silently misses the analyzer bridge
state. The backup contains `.env`, so treat it as sensitive. Copy backups off
the server as part of the Ministry's disaster recovery plan.

Read [docs/backup-restore.md](docs/backup-restore.md) **before** restoring.
Restoring the database as the wrong user takes the site down.

### Upgrading to a new release

1. Take a backup: `sudo ./scripts/backup.sh`
2. Fetch and switch to the new tag:

   ```bash
   git fetch --tags
   git checkout <new-release-tag>
   ```

3. Pull the new images and restart:

   ```bash
   docker compose pull
   docker compose up -d
   ```

4. Wait for `healthy`, then log in and spot-check a recent order.

To roll back, check out the previous tag and run the same `pull` and
`up -d`. If the new version changed the database, restore the backup from
step 1.

### Troubleshooting

| Symptom | Fix |
|---|---|
| `Failed to save checksums file` in the log, catalog reloads every start | `./scripts/fix-config-permissions.sh`, then restart |
| Analyzer bridge fails to open its state store | `./scripts/init-bridge-state.sh`, then restart |
| `admin` / `adminADMIN!` still works | `./scripts/set-admin-password.sh` |
| Browser shows a certificate warning after an upgrade | `COMPOSE_FILE` line missing from `.env`; add it, then `docker compose up -d --force-recreate proxy` |
| Let's Encrypt dry run fails | Check the DNS record points at this server and port 80 is open from the internet |
| A service keeps restarting | `docker compose logs <service>` and read the last error |

## Loading the PNG test catalog

The test catalog (tests, sample types, test sections, result options,
dictionary entries, lab roles) is loaded from CSV files at start-up. The
files live in:

```
configs/configuration/backend/<domain>/png-*.csv
```

The PNG catalog files are prepared by the catalog team (CPHL and DIGI). To
load a new or updated set on a server:

1. Take a backup.
2. Copy each file into its folder, replacing the existing `png-*.csv`
   (for example `tests/png-tests.csv`, `sample-types/png-sample-types.csv`).
3. Fix permissions and restart the web application:

   ```bash
   ./scripts/fix-config-permissions.sh
   docker compose restart oe.openelis.org
   ```

4. Check the log for each file:

   ```bash
   docker compose logs oe.openelis.org | grep -i "configuration"
   ```

   You should see `Successfully loaded ...` for changed files and
   `unchanged (checksum matches). Skipping.` for the rest. Any error names
   the file and row; send it back to the catalog team rather than editing
   the file on the server.

Loading is safe to repeat: existing entries are updated, not duplicated.

> **Catalog status.** The test catalog in this repository is a placeholder
> for testing and training. It is not the PNG catalog and must not be used
> for patient results. Replace it with the PNG catalog files before go-live.
> `roles/png-lab-roles.csv` and `test-sections/png-test-sections.csv` are
> currently empty.

## PNG configuration included

| Setting | Value | File |
|---|---|---|
| Patient address | Province and District as dropdowns (22 provinces, 90 districts), then LLG and Village / Ward as free text | `address-hierarchy/png-levels.csv`, `png-values.csv` |
| Phone numbers | Optional `+675`, then 8-digit mobile (`7XXX XXXX`, `8XXX XXXX`) or 7-digit fixed line (`XXX XXXX`); international numbers accepted in `+CC` form | `site-information/png-site-information.csv`, `configs/properties/SystemConfiguration.properties` |
| Interface language | English | `locales/png-locales.csv` |

Address and phone settings can be adjusted later in the application under
Administration.

## Analyzers

The analyzer bridge is included. It listens for ASTM connections on port
12000 and picks up result files dropped into its watched import folder.
Ready-made profiles for common analyzers are in `configs/analyzer-profiles/`
(ASTM, HL7 and file formats). Connecting an analyzer is done with the DIGI
analyzer team; ICT staff only need to make sure the analyzer can reach the
server on the lab network.

`scripts/converters/` holds small tools that reshape some vendors' export
files before the bridge reads them. See
[scripts/converters/README.md](scripts/converters/README.md).

## For maintainers

### Versioning

`main` tracks upstream `develop` images (`itechuw/openelis-global-2:develop`
and related). Releases are cut from `main` by the **Release** GitHub Actions
workflow, which pins every image to an exact `tag@sha256:<digest>` so that a
release tag always installs the same bytes. Distro release numbers are
independent of upstream OpenELIS version numbers.

To cut a release: **Actions > Release > Run workflow**, then fill in:

- `distro_version`: the new tag; must not already exist
- `oe_version`, `bridge_version`: upstream image tags to pin
- `base_ref` (optional): branch or commit to release from; default `main`
- `allow_develop_pins` (optional): leave off for real releases; the workflow
  fails if any pin is `:develop`, `:latest` or missing a digest
- `draft` (default on) and `prerelease` (optional)

The workflow refreshes digests with `scripts/pin-versions.sh`, checks them
with `scripts/check-release-pins.sh`, commits the pinned
`docker-compose.yml` on the tag only, builds the tarball with
`scripts/build-tarball.sh`, and drafts a GitHub Release with notes from the
upstream releases plus the distro commit log. Review the draft, then
publish.

To refresh pins by hand:

```bash
./scripts/pin-versions.sh <oe-tag|develop> <bridge-tag|develop>
git diff docker-compose.yml
```

### Why the admin password needs a script

OpenELIS creates the `admin` account on first start from a password hash
built into the web application image (`ARG DEFAULT_PW` at image build time).
A distro that uses published images cannot change that, so
`scripts/set-admin-password.sh` sets the real password after start-up and
verifies it through the login endpoint.

### Catalog loading details

`ConfigurationInitializationService` loads every `*.csv` in each domain
folder (the `png-` prefix is a naming convention, not a filter) and records a
SHA-256 checksum per file name so unchanged files are skipped on later
starts. OpenELIS also supports instance-scoped overlays via
`OPENELIS_CONFIGURATION_INSTANCE_ID`
([source](https://github.com/I-TECH-UW/OpenELIS-Global-2/blob/develop/src/main/java/org/openelisglobal/configuration/service/ConfigurationInitializationService.java#L125-L145));
this distro does not use them.

### Development and testing

Playwright end-to-end tests, a mock analyzer and development overlays live
in the companion `openelis-png-test-harness` repository, which consumes this
distro at a tag.

[docs/template-source-inventory.md](docs/template-source-inventory.md)
classifies which files are generic and which are country-specific, for
extracting a shared distro template.
