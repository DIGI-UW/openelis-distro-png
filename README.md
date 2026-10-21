# OpenELIS Global: Papua New Guinea distribution

This repository is the deployment package for OpenELIS Global in Papua New
Guinea. It is a Docker Compose stack that brings up the full OpenELIS system
(database, web application, FHIR API, front end, HTTPS proxy and analyzer
bridge) with the PNG configuration already in place.

It is written for the National Department of Health ICT staff who install and
run OpenELIS servers. Developer and release notes are at the end.

The current delivery targets a fresh **online, single-server PNG installation**.
Minimum fresh-install security remains part of the target. Offline installation,
a general certificate rotation/upgrade framework, existing-data re-encryption,
standby qualification and migration automation are outside this work. The existing
training server will be migrated separately by the operator. See the
[target installation plan](docs/remediation-roadmap.md) for acceptance checks and
the [persistent-state handoff](docs/target-state.md) and
[validation record](docs/validation-2026-10-21.md). Existing installations are not
remediated by these fresh-target changes.

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
| Software | Docker Engine with the Compose v2 plugin (`docker compose`), `git`, Python 3 |
| Network | Internet access during install to pull images; ports 80 and 443 reachable by users |
| Hostname | A DNS name for the server (for example `lab.health.gov.pg`) pointing at its public IP, for the Let's Encrypt certificate |
| Access | A user with `sudo` rights |

Check Docker is ready before you start:

```bash
docker --version
docker compose version
```

### Ports

The application and management ports bind to localhost. Only 80 and 443 need
to be reachable by lab users. Restrict port 12000 to the instrument network.

| Port | Used by | Who needs it |
|---|---|---|
| 80, 443 | Web interface (HTTPS proxy); port 80 also answers Let's Encrypt checks | All users, and the internet for port 80 |
| 12000 | Analyzer bridge, ASTM listener | Analyzers on the lab network only |
| 8442 | Bridge API and HTTP instrument input | Local by default; set `BRIDGE_HTTPS_BIND_ADDRESS` to a lab-network interface only when HTTP instruments need it |
| 8080, 8443 | Web application (behind the proxy) | Local only |
| 8081, 8444 | FHIR API | Local only, or the consolidated server if connected |

## Choosing a version

Always install from a **release tag**, not from `main`. The `main` branch
may contain an unvalidated candidate. Images in this candidate are pinned by
digest, including those labelled `develop`; pinning fixes their bytes but does
not establish that they passed acceptance. Check the release validation record.

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
```

Run it before the first start. It is safe to run again at any time.
Skipping it makes OpenELIS log `Failed to save checksums file` and reload
the whole catalog on every start.

`configs/bridge-state` needs no manual step: the `bridge-state-init` service
in `docker-compose.yml` claims it for UID 9257 on every `up`, before the
analyzer bridge starts. `./scripts/init-bridge-state.sh` does the same thing
by hand and is still the repair path after a restore (see
[docs/backup-restore.md](docs/backup-restore.md)).

### 4. Start the stack

Network-connected analyzers need no analyzer host folder. If your instruments
export files to a host directory, complete [File-based analyzers](#file-based-analyzers)
before starting. On upgrades, an existing `ANALYZER_HOST_MOUNT` setting now
also requires the optional Compose file; it no longer creates a mount by itself.

Check the analyzer mount configuration (requires Python 3):

```bash
python3 scripts/check-analyzer-mounts.py
```

Then run the online installer:

```bash
./scripts/install.sh
docker compose ps
```

It refuses default administrator/database passwords, pulls the exact images,
generates this installation's private keys and independent encryption secret,
waits for the application, changes and verifies the administrator password,
and only then starts the browser proxy. Use it for a fresh target; it does not
migrate an existing server. If initialization finds existing unrecognized keys,
it stops without replacing them. See [security and state](docs/target-state.md).

Wait until `oe.openelis.org` shows `healthy`. The first start takes several
minutes while the database is created and the catalog is loaded. Allow up to
30 minutes for a first boot on a slow host; readiness changes as soon as it
finishes. A restart reuses configuration checksums.

### 5. Set the admin password

The installer has already applied and verified the password. For a manual
installation, run `./scripts/set-admin-password.sh` before starting the proxy.

### 6. Set up HTTPS

Follow [HTTPS with Let's Encrypt](#https-with-lets-encrypt) below. Until you
do, the server uses a self-signed certificate and browsers show a warning.

### 7. Pair the analyzer Bridge

Sign in as Global Admin, open Analyzers and enter the single-use pairing code
from `docker compose logs openelis-analyzer-bridge`. Keep that code private.
Pair over the stack's private network. Saved analyzer connections determine
allowed senders; logs can help identify addresses but do not authorize them.
Pairing and one synthetic delivery must pass before accepting the installation.

### 8. Log in

Open `https://<your-hostname>/` and sign in as `admin` with the password you
set.

## Set the admin password (mandatory)

Putting `OE_ADMIN_PASSWORD` in `.env` does **not** change the login password
on its own. `scripts/install.sh` applies it before exposing the browser proxy.
For a manual installation, keep the proxy stopped until you run:

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
Bridge fallback credential and installer checks use it; paired forwarding uses
certificate identity.

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

If `COMPOSE_FILE` is already set, append `:compose.letsencrypt.yaml` to it.
Keep any analyzer-files or high-availability overlays enabled.

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
   python3 scripts/check-analyzer-mounts.py
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
| Analyzer bridge fails to open its state store | `docker compose up -d bridge-state-init`, then restart the bridge |
| `admin` / `adminADMIN!` still works | `./scripts/set-admin-password.sh` |
| Browser shows a certificate warning after an upgrade | `COMPOSE_FILE` line missing from `.env`; add it, then `docker compose up -d --force-recreate proxy` |
| Let's Encrypt dry run fails | Check the DNS record points at this server and port 80 is open from the internet |
| `Mounts denied` for an analyzer directory | Run `python3 scripts/check-analyzer-mounts.py`. For file-based analyzers, share the configured directory with Docker Desktop; `sudo` does not bypass file sharing. Without file-based analyzers, remove the analyzer-files overlay and obsolete `ANALYZER_HOST_MOUNT` setting. |
| A service keeps restarting | `docker compose logs <service>` and read the last error |

## Loading the PNG test catalog

The test catalog (tests, sample types, test sections, result options,
dictionary entries, panels) is loaded from CSV files at start-up. The files
live in:

```
configs/configuration/backend/<domain>/png-*.csv
```

The PNG catalog files are prepared by the catalog team (CPHL and DIGI). To
load a new or updated set on a server:

1. Take a backup.
2. Copy each file into its folder, replacing the existing `png-*.csv`
   (for example `tests/png-tests.csv`, `sample-types/png-sample-types.csv`,
   `panels/png-panels.csv`).
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

### What ships in this repository

The distro includes the **CPHL test catalog**, generated from the CPHL test
workbook:

| File | Contents |
|---|---|
| `tests/png-tests.csv` | 394 tests |
| `sample-types/png-sample-types.csv` | 57 sample types |
| `test-sections/png-test-sections.csv` | 6 test sections |
| `test-results/png-test-results.csv` | 1,856 result definitions |
| `dictionaries/png-dictionary-entries.csv` | 734 result options, plus analyzer result options and demographic settings |
| `panels/png-panels.csv` | 71 panels |
| `eqa-programs/png-eqa-programs.csv` | 6 national EQA schemes run by CPHL (HIV serology, HIV viral load, EID, HIV recency, COVID-19 molecular, TB microscopy) |

> **Pending CPHL review.** This catalog has not yet been signed off by CPHL
> and must be reviewed before go-live. In particular:
>
> - LOINC codes and units of measure are blank (they are not in the source
>   workbook and were not guessed).
> - Sample type abbreviations, result types (numeric / text / select list)
>   and normal flags were generated and need checking.
> - Test names with brackets were simplified for the loader
>   (for example `Amikacin (AK)` is loaded as `Amikacin AK`).
>
> `roles/png-lab-roles.csv` is empty; lab roles use the OpenELIS defaults.

## PNG configuration included

| Setting | Value | File |
|---|---|---|
| Patient address | Province and District as dropdowns (22 provinces, 90 districts), then LLG and Village / Ward as free text | `address-hierarchy/png-levels.csv`, `png-values.csv` |
| Phone numbers | Optional `+675`, then 8-digit mobile (`7XXX XXXX`, `8XXX XXXX`) or 7-digit fixed line (`XXX XXXX`); international numbers accepted in `+CC` form | `site-information/png-site-information.csv`, `configs/properties/SystemConfiguration.properties` |
| Interface language | English (Papua New Guinea) as the default, plus English | `locales/png-locales.csv` |

Address and phone settings can be adjusted later in the application under
Administration.

## Analyzers

The analyzer bridge is included. It listens for ASTM connections on port
12000. Network-connected analyzers require no host file mount. File-based
analyzers can use the optional shared folder described below.
Available profiles come from the pinned Bridge image and are shown in the
application. The older files under `configs/analyzer-profiles/` do not establish
which profiles are active in this image. The bounded acceptance test uses its
Thermo QuantStudio file profile; other instruments need their own mapping and
connection validation with the DIGI analyzer team. ICT staff must restrict
instrument access to the lab network.

`scripts/converters/` holds small tools that reshape some vendors' export
files before the bridge reads them. See
[scripts/converters/README.md](scripts/converters/README.md).

### File-based analyzers

Only enable this when instruments export results to a folder on the server
(for example an NFS share or a USB drive). Uploaded files and the Bridge's
internal persistent storage remain available without this host mount.

For a folder inside the distribution, run from the distribution directory:

```bash
mkdir -p configs/analyzer-drops
```

Add these settings to `.env`:

```dotenv
COMPOSE_FILE=docker-compose.yml:compose.analyzer-files.yaml
ANALYZER_HOST_MOUNT=./configs/analyzer-drops
```

If `COMPOSE_FILE` already enables other optional files, append
`:compose.analyzer-files.yaml` to the existing value. For example, with
Let's Encrypt:

```dotenv
COMPOSE_FILE=docker-compose.yml:compose.letsencrypt.yaml:compose.analyzer-files.yaml
```

For an existing external share, set `ANALYZER_HOST_MOUNT` to that directory
instead. Ensure the share is mounted before starting Docker services; do not
create an empty replacement folder for a missing network share. On Docker
Desktop, the directory must be allowed under **Settings > Resources > File
Sharing**. Production servers remain Ubuntu; macOS is a local validation option.

Both OpenELIS and the Bridge see this directory at `/data/analyzer-drops`.
Configure an instrument's watched folder using that container path, for example
`/data/analyzer-drops/instrument-a`, not its host path. The mounts are read-only;
neither service can move or delete the instrument's source files. Grant directory
traversal and file read access to the service users (OpenELIS UID 8443 and Bridge
UID 9257), using the site's access-control policy.

Before starting, pull the selected Bridge image, then check Docker can mount and
read the directory as both users:

```bash
docker compose pull openelis-analyzer-bridge
python3 scripts/check-analyzer-mounts.py
docker compose up -d
```

The check runs disposable containers with no network and no application services.
It uses the selected Docker context and the same Compose file selection as
`docker compose up`. It does not print resolved passwords or alter source files.
It checks directory access, not every result file's permissions or a complete
instrument workflow. Custom container user settings are used when supplied;
otherwise the published service user IDs above are checked.

**Upgrading a file-based installation:** retain its existing host directory,
add `compose.analyzer-files.yaml` to `COMPOSE_FILE`, and run the check before
recreating services. Confirm each configured instrument's watched path still
matches. Setting `ANALYZER_HOST_MOUNT` alone is no longer enough. To stop using
host file ingestion, first disable the affected instrument connections, then
remove the optional file and the variable from `.env` and recreate services.
This does not delete the directory or its files.

For startup diagnosis, check `docker context show`, the `COMPOSE_FILE` setting,
and any local `compose.yaml` or override files. Run `docker compose ps --all`
and `docker compose logs bridge-state-init certs` to inspect initialization.
An initializer exiting with code zero is normal; a running container alone does
not prove the application is ready. Avoid sharing a full `docker compose config`
dump because it contains credentials.

## For maintainers

### Versioning

`main` may select upstream `develop` images (`itechuw/openelis-global-2:develop`
and related). Releases are cut from `main` by the **Release** GitHub Actions
workflow, which requires every image to have a committed `tag@sha256:<digest>`
reference so a release installs the tested candidate's image bytes. Distro release numbers are
independent of upstream OpenELIS version numbers.

To cut a release: **Actions > Release > Run workflow**, then fill in:

- `distro_version`: the new tag; must not already exist
- `oe_version`, `bridge_version`: upstream tags already pinned in `base_ref`
- `allow_develop_pins`: allow development labels for a candidate; digest pins
  remain mandatory
- `base_ref` (optional): branch or commit to release from; default `main`
- `draft` (default on) and `prerelease` (optional)

The workflow checks the committed pins and requested labels, tags the selected
revision, builds the tarball and drafts a GitHub Release. It does not resolve
image tags again during publication. Review the acceptance evidence before
publishing; a digest proves image identity, not successful validation.

To refresh pins by hand:

```bash
./scripts/pin-versions.sh <oe-tag|develop> <bridge-tag|develop>
git diff docker-compose.yml
```

Test the resulting candidate and commit its pins before running Release.

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

Validate optional analyzer mounts and their combinations with other Compose files:

```bash
python3 -m unittest discover -s tests -v
```

To also run disposable Docker probes for both service users, pull the Bridge
image for the architecture specified by the distro, then enable the runtime test:

```bash
docker compose pull openelis-analyzer-bridge certs
PNG_TEST_SECURITY=1 PNG_TEST_DOCKER_MOUNTS=1 python3 -m unittest discover -s tests -v
```

The tests use the pinned images, temporary synthetic files and disposable
security volumes. They do not start the application stack. Run on Linux to
exercise native permission denial as well as key uniqueness and restart checks.

Playwright end-to-end tests, a mock analyzer and development overlays live
in the companion `openelis-png-test-harness` repository, which consumes this
distro at a tag.

[docs/template-source-inventory.md](docs/template-source-inventory.md)
classifies which files are generic and which are country-specific, for
extracting a shared distro template.
