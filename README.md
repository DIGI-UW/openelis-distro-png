# openelis-distro-png

OpenELIS Global deployment package for Papua New Guinea — Docker Compose stack
with the Papua New Guinea configuration profile, analyzer bridge, and lab-data
converters bundled.

This repo IS the deployment artifact: every tagged release is consumable
as a [GitHub auto-archive](https://github.com/DIGI-UW/openelis-distro-png/releases),
a `git clone --branch <tag>`, or a downloaded Release tarball. Ozone-style
consumers and direct implementers all use the same versioned tag.

## Quickstart (localhost demo)

```bash
git clone https://github.com/DIGI-UW/openelis-distro-png
cd openelis-distro-png

./scripts/fix-config-permissions.sh   # before first start — see note below
./scripts/init-bridge-state.sh

docker compose up -d
```

Then open https://localhost/ in your browser:

| URL | Credentials |
|---|---|
| https://localhost/ | `admin` / `adminADMIN!` |

`scripts/fix-config-permissions.sh` hands `configs/configuration` to UID 8443
(the webapp's `tomcat_admin`) with group write for you. Skip it and every
boot logs `Failed to save checksums file ...` for all 15 catalog domains and
re-imports the whole catalog each time. Run it before the first
`docker compose up -d`; it is idempotent.

`docker-compose.yml` ships sensible localhost-demo defaults (DB password, TLS
material paths) so the stack boots out of the box without a local `.env`. To
override anything for production, copy `.env.example` to `.env` and edit.
**`.env` is gitignored — never commit it.**

## Deploying a real site

Everything in Quickstart, plus:

```bash
cp .env.example .env
# set OE_DB_PASSWORD, ADMIN_PASSWORD and OE_ADMIN_PASSWORD to site values.
# OE_ADMIN_PASSWORD must satisfy the OpenELIS password policy — .env.example
# spells it out; a hyphen will be rejected.

./scripts/fix-config-permissions.sh
./scripts/init-bridge-state.sh
docker compose up -d

docker compose ps                    # wait for oe.openelis.org -> healthy
./scripts/set-admin-password.sh      # MANDATORY — see below
```

### The admin password step is not optional

`OE_ADMIN_PASSWORD` in `.env` does **not** by itself change the login
password. OpenELIS creates the `admin` account on first boot from a bcrypt
hash baked into the webapp image at *build* time (upstream `ARG DEFAULT_PW`
→ `adminPassword.txt` on the WAR classpath). A distro that ships pinned
upstream images cannot change a build argument, so a fresh site accepts the
published default `admin` / `adminADMIN!` until you run:

```bash
./scripts/set-admin-password.sh
```

It applies `OE_ADMIN_PASSWORD`, then verifies through OpenELIS's own login
endpoint that the configured password is accepted and `adminADMIN!` is
rejected. Re-check at any time with `./scripts/set-admin-password.sh --check`.

Earlier revisions of this distro carried `DEFAULT_PW=${OE_ADMIN_PASSWORD}` in
`docker-compose.yml`; it was read at build time only and had no effect at
runtime, so sites went live on the public default.

## Image pinning

Every service in `docker-compose.yml` is pinned directly to a literal
`repo:tag@sha256:<digest>` reference:

```yaml
image: itechuw/openelis-global-2:3.2.1.6@sha256:0fb3a481...
image: itechuw/openelis-analyzer-bridge:3.0.1@sha256:6d43bf5b...
```

The tag is human-readable documentation ("this is the 3.2.1.6 release");
the digest is the immutability lock — `docker compose pull` returns the
exact bytes regardless of when or where it runs, even if upstream
republishes the tag.

To bump pins (maintainer workflow) — accepts any published upstream tag,
release name or `develop`:

```bash
./scripts/pin-versions.sh                       # refresh digests, current tags
./scripts/pin-versions.sh 3.2.1.7 3.0.2         # bump both to release tags
./scripts/pin-versions.sh develop 3.0.1         # OE to current develop snapshot; bridge to release
./scripts/pin-versions.sh develop develop       # both at current develop snapshots
git diff docker-compose.yml                            # review
git commit docker-compose.yml -m "chore: bump pins to ..."
```

Distro tags release independently of upstream OE versioning — distro
`3.2.2.0` could ship with OE `3.2.1.6` images, OE `develop` snapshots,
or any mix.

## Cutting a release

Releases are produced by the `Release` GitHub Actions workflow
(`workflow_dispatch`). The workflow collects all version inputs up front,
refreshes image digests in `docker-compose.yml`, validates the result is
release-shaped, then tags and publishes — no local `git tag`/`git push`
step.

To cut a release:

1. **Actions → Release → Run workflow** in the GitHub UI.
2. Fill in the inputs:
   - `distro_version` — e.g. `3.2.2.0`. Must not collide with an existing tag.
   - `oe_version` — OE image tag, e.g. `3.2.1.6`.
   - `bridge_version` — Analyzer Bridge image tag, e.g. `3.0.1`.
   - `base_ref` *(optional)* — branch or commit to release from; defaults to `main`. Useful for backports.
   - `allow_develop_pins` *(optional)* — leave **off** for normal releases. The workflow fails if any image pin is non-release (`:develop`/`:latest`/missing digest) unless this is on.
   - `draft` *(optional)* — leave **on** (default) to review the Release before publishing.
   - `prerelease` *(optional)* — flag the Release as pre-release.
3. Click **Run workflow**.

The workflow then:

1. Validates `distro_version` shape, captures the previous tag, and confirms the new tag doesn't already exist.
2. Runs `scripts/pin-versions.sh <oe> <bridge>` to refresh digests in `docker-compose.yml`.
3. Runs `scripts/check-release-pins.sh` to assert every pin is release-shaped.
4. If digests changed, commits the diff (a release commit reachable **only via the new tag**); otherwise tags the existing `base_ref` HEAD.
5. Builds the release tarball via `scripts/build-tarball.sh`.
6. Publishes a GitHub Release with notes assembled from the upstream OE and Analyzer Bridge release bodies plus the distro-side commit log since the previous distro tag, with the tarball attached.

Review the draft Release in the GitHub UI, then publish when satisfied.
At any commit (`main` or a release tag), `docker-compose.yml` carries fully
resolved literal image references; consumers cloning at the tag (or
downloading the auto-archive or the Release tarball) get a self-contained,
byte-reproducible package.

## Production deployment

| Topic | Pointer |
|---|---|
| Setting the in-app admin password (mandatory) | `./scripts/set-admin-password.sh` |
| Backup and restore | [docs/backup-restore.md](docs/backup-restore.md) |
| Let's Encrypt TLS for a public hostname | [docs/letsencrypt.md](docs/letsencrypt.md) |
| `Failed to save checksums` / permission errors on `configs/` | `./scripts/fix-config-permissions.sh` |
| Bridge state store fails to open | `./scripts/init-bridge-state.sh` |
| Template extraction source classification | [docs/template-source-inventory.md](docs/template-source-inventory.md) |

Both the Let's Encrypt overlay and
`scripts/generate-letsencrypt-certs.sh` read `LETSENCRYPT_*` from `.env`.
Start from `.env.example` (uncomment the LE block) and follow
`docs/letsencrypt.md` for the full walkthrough.

Back up with `sudo ./scripts/backup.sh` — it must run as root, or the
archive silently omits `configs/bridge-state`. Read
[docs/backup-restore.md](docs/backup-restore.md) before restoring: restoring
the dump as `-U postgres` takes the site down.

## Lab-data utilities

`scripts/converters/` holds standalone host-side preprocessors that
normalize vendor-specific analyzer exports into the shape each
`configs/analyzer-profiles/file/*.json` profile expects, before the
bridge picks the file up. See [scripts/converters/README.md](scripts/converters/README.md)
for per-script usage, the adapt-at-host design rationale, and operational
placement.

## Catalog configuration

`configs/configuration/backend/<domain>/png-*.csv` are this distro's catalog
data — lab roles, tests, sample types, test sections, test results,
dictionary entries, and address hierarchy levels/values. OE auto-imports them
at startup via `ConfigurationInitializationService`, with SHA-256 checksum
tracking that skips re-import on subsequent boots if file content is
unchanged. Imports are idempotent (upsert by domain key), so renaming or
re-running is safe.

The `png-` prefix marks these as this deployment's catalog slot, not generic
samples (the prior `example-` prefix was misleading: the loader doesn't filter
by filename prefix — any `*.csv` in each domain subdirectory is processed).

> **The contents are not yet Papua New Guinea's data.** These files still hold
> the Madagascar payload this repo was branched from, and nothing in them has
> been localized for PNG:
>
> | File | Still contains |
> |---|---|
> | `address-hierarchy/png-values.csv` | 110 Malagasy provinces / regions / districts (Toamasina, Alaotra-Mangoro, …) |
> | `address-hierarchy/png-levels.csv` | `Fokontany`, a Malagasy administrative unit |
> | `site-information/png-site-information.csv` | phone validation for `+261` (Madagascar; PNG is `+675`) |
> | `tests/png-tests.csv`, `sample-types/`, `dictionaries/` | French localization columns, no Tok Pisin |
> | `roles/png-lab-roles.csv`, `test-sections/png-test-sections.csv` | header only — empty |
>
> Replacing this content with the PNG catalog is outstanding work. Until then
> a deployed site carries Madagascar reference data under PNG filenames.

### Upgrading a site across the `madagascar-*` → `png-*` rename

`ConfigurationInitializationService` keys its checksums by **file basename**
(`resource.getFilename()`), so on a site that already ran the old filenames
the first boot after this change re-imports all ten renamed files once, then
settles:

```
png-tests.csv ... Successfully loaded tests configuration      # first boot
png-tests.csv ... unchanged (checksum matches). Skipping.      # every boot after
```

That re-import is safe — the handlers upsert by domain key, and the file
contents did not change with the rename. The stale `madagascar-*.csv` entries
left behind in each `<domain>-checksums.properties` are inert; delete the
checksum files if you want them tidied, and OE will regenerate them on the
next start. Fresh installs have no checksum files and are unaffected.

If this distro is ever reused as a template by other deployments, OE
also supports `OPENELIS_CONFIGURATION_INSTANCE_ID` for instance-scoped
subdirectory overlays
([ConfigurationInitializationService.java:125-145][cis]) — set the
env var to the customer's instance id and place that customer's CSVs
under `<domain>/<instance-id>/*.csv` to scope them. Not implemented
here because this artifact is Papua New Guinea-specific.

[cis]: https://github.com/I-TECH-UW/OpenELIS-Global-2/blob/develop/src/main/java/org/openelisglobal/configuration/service/ConfigurationInitializationService.java#L125-L145

## Developing or testing this distro

The dev workspace, Playwright E2E tests, build overlays, and dev
orchestration scripts live in the sibling
[openelis-png-test-harness][harness] repo. The harness consumes
this distro at a tag (or as a sibling clone) and adds a mock analyzer +
test runner on top.

[harness]: https://github.com/DIGI-UW/openelis-png-test-harness