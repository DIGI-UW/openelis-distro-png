# Moving a site from openelis-docker to this distribution

For a server that runs OpenELIS from an `openelis-docker` ("allinone")
folder and should run from this distribution instead, keeping its data. The
old folder is never modified, so going back is one command.

Plan a window outside working hours. The stack is down from the start of the
cutover until the web application reports healthy: allow 30 to 45 minutes,
most of it the first start (database migrations on the copied database).

## What moves where

| Old folder | This distribution | How |
|---|---|---|
| `.env` | `.env` | rebuilt by `prepare` (credentials and the database encryption key kept) |
| `configs/database/data` | `data/db` | copied while the old stack is stopped |
| `configs/bridge-state` | `data/bridge` | copied, owners kept (UID 9257) |
| `configs/branding`, `configs/nce-attachments` | `data/webapp/...` | copied |
| volume `<folder>_lucene_index-vol` | `data/webapp/lucene` | copied |
| volume `<folder>_key_trust-store-volume` | `data/tls` | **not copied**: this stack generates its own |
| `configs/menu/menu_config.json`, translations | tracked in `configs/` | already part of the distribution |
| `configs/configuration/backend/*.csv` | not used | the catalog lives in the database; `OE_CONFIGURATION_AUTOCREATE=false` |

## Before the window

Nothing here stops or changes the running site.

1. Check out this distribution next to the old folder (the branch or release
   tag you are deploying).
2. Prepare:

   ```bash
   sudo ./scripts/migrate-from-allinone.sh prepare /path/to/openelis-docker
   ```

   It writes `.env` (mode 0600; an existing one is kept as
   `.env.pre-migration-<time>`), validates the compose files and pulls every
   image. It is safe to run again; the generated pairing code and keystore
   passwords are kept.
3. Read `.env` once. Check:
   - `OE_ENCRYPTION_PASSWORD`: copied from the old stack. It must not change.
   - `ANALYZER_BRIDGE_PAIRING_CODE`: you will need it after the first start.
   - The Let's Encrypt block: present when the host's certbot keeps exactly
     one certificate under `/etc/letsencrypt/live`.
4. Check free disk space: at least twice the size of
   `configs/database/data`, plus the dump.

## In the window

1. **Cut over.** Dumps the database and the bridge state into
   `backups/cutover-<time>/`, stops the old stack, copies the data:

   ```bash
   sudo ./scripts/migrate-from-allinone.sh cutover /path/to/openelis-docker
   ```

2. **Start.**

   ```bash
   docker compose up -d
   docker compose logs -f oe.openelis.org     # Ctrl-C once it is up
   docker compose ps                          # wait for oe.openelis.org: healthy
   ```

   The `init` service runs first and logs `generating this site's internal
   certificate` and `data tree ready`.

3. **Pair OpenELIS with the analyzer bridge.** The copied database remembers
   the old bridge, so OpenELIS does not pair by itself. In Admin > Analyzers,
   pair with the code from:

   ```bash
   grep ANALYZER_BRIDGE_PAIRING_CODE .env
   ```

   Results analyzers send before this wait in the bridge and are delivered
   once paired.

4. **Check.**
   - The site opens over HTTPS with no certificate warning.
   - Log in; the banner, site name and menus are as before.
   - Recent orders and results are there.
   - Admin > Analyzers shows the bridge as paired and lists the analyzers.
   - `docker compose logs openelis-analyzer-bridge | grep -i listening` shows
     port 12001 (host port 12000).

5. **Tidy the host.** Anything on the server that still points at the old
   folder or the old database:
   - Scheduled backups: replace them with `sudo ./scripts/backup.sh`.
   - Scripts that write settings straight into the database at boot: remove
     them; settings belong in Administration or
     `configs/properties/SystemConfiguration.properties`.
   - A host certbot keeps working: its deploy hook restarts
     `openelisglobal-proxy`, which is the same container name. Remove any
     cron job running `scripts/generate-letsencrypt-certs.sh` in that case.

## Going back

```bash
sudo ./scripts/migrate-from-allinone.sh rollback /path/to/openelis-docker
```

Stops this stack and starts the old one exactly as it was at cutover time.
Anything entered on this stack since then is not carried back. `data/` is
kept for inspection.

## Differences to expect

- **Analyzer ports.** One shared ASTM listener on host port 12000 serves every
  TCP analyzer. Instruments set to send anywhere else must be set to 12000.
  When two analyzers of the same kind share it, set `host` or `senderId` on
  their connections (Admin > Analyzers).
- **Analyzers after the mapping migration.** A database that went through
  Liquibase changeset `124-analyzer-mapping-baseline-migration` has every
  analyzer inactive with no mapping, by design. Set each one up again in
  Admin > Analyzers; the old mappings are in `configuration_import_run`
  (see OpenELIS `docs/analyzers/mapping-baseline-migration.md`).
- **Settings from the properties file.** Every uncommented line in
  `configs/properties/SystemConfiguration.properties` is written to the
  database at each start. The distribution keeps site-specific values (banner,
  site name) out of it; PNG-wide values such as phone formats are applied.
- **Internal certificates.** This stack uses its own certificate between
  services instead of the one shared by every OpenELIS install. Browsers are
  unaffected.
