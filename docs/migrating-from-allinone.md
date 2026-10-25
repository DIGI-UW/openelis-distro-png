# Moving a site from openelis-docker to this distribution

> Historical migration outline, not validated for the fresh-install candidate.
> The current initializer refuses older or partial TLS directories and does not
> convert encrypted database secrets. Do not follow these steps against a live
> site until a separate migration plan covers its database and retained keys.

For a server that runs OpenELIS from an `openelis-docker` ("allinone")
folder and should run from this distribution instead, keeping its data.

The data is copied, never moved: the old folder is not modified, so it
stays the backup, and going back means starting it again.

Plan a window outside working hours. The site is down from stopping the old
stack until the web application reports healthy: allow 30 to 45 minutes,
most of it the first start (database migrations on the copied database).

The commands below use `/srv/openelis-docker` for the old folder and
`/srv/openelis-distro-png` for this one; use your own paths.

## Before the window

Nothing here touches the running site.

1. Check out this distribution next to the old folder (the branch or
   release tag you are deploying).
2. Write `.env` from `.env.example` (`cp .env.example .env`, then edit; keep
   it mode 0600). Carry these over from the old stack:

   | Setting | Value |
   |---|---|
   | `OE_DB_PASSWORD`, `ADMIN_PASSWORD`, `OE_ADMIN_PASSWORD` | the old `.env`'s values |
   | `OE_ENCRYPTION_PASSWORD` | the key the old database's secrets are encrypted with: the value of `encryption.general.password` in the old `configs/properties/common.properties`, or the variable it names (usually the old `SSL_KEYSTORE_PASSWORD`). It must not change |
   | `OE_CONFIGURATION_AUTOCREATE` | `false`: the catalog lives in the database; don't import the baseline over it |

   Generate new ones for this stack:

   | Setting | Value |
   |---|---|
   | `ANALYZER_BRIDGE_PAIRING_CODE` | `openssl rand -hex 16` |
   | `SSL_KEYSTORE_PASSWORD`, `SSL_TRUSTSTORE_PASSWORD` | `openssl rand -hex 16` each (they protect this stack's own internal keystores) |

   If a certbot on the host already keeps the site's certificate, add the
   Let's Encrypt block with `LETSENCRYPT_DIR=/etc/letsencrypt` and
   `CERTBOT_WEBROOT` set to its webroot, and include
   `compose.letsencrypt.yaml` in `COMPOSE_FILE` (see
   [letsencrypt.md](letsencrypt.md)).
3. Check and pre-pull:

   ```bash
   docker compose config -q
   docker compose pull
   ```

   Pulling updates the shared `:develop` tags; the running old stack keeps
   the images it started with.
4. Check free disk space: at least the size of the old
   `configs/database/data` again.

## In the window

1. Stop the old stack (its volumes and folders stay as they are):

   ```bash
   cd /srv/openelis-docker && docker compose down
   ```

2. Copy its data:

   ```bash
   sudo mkdir -p /srv/openelis-distro-png/data
   sudo cp -a /srv/openelis-docker/configs/database/data /srv/openelis-distro-png/data/db
   sudo cp -a /srv/openelis-docker/configs/bridge-state /srv/openelis-distro-png/data/bridge
   ```

   If the old `configs/branding` or `configs/nce-attachments` hold files,
   copy them into `data/webapp/branding` and `data/webapp/nce-attachments`
   the same way.
3. Start:

   ```bash
   cd /srv/openelis-distro-png && docker compose up -d
   docker compose ps        # wait for oe.openelis.org: healthy
   ```

   The `init` service runs first: it sets owners on `data/` and generates
   this stack's internal certificate and keystores.
4. Clear the old bridge pairing. OpenELIS pairs by itself with
   `ANALYZER_BRIDGE_PAIRING_CODE` from `.env`, but only while it has no
   pairing record, and the copied database holds the old bridge's:

   ```bash
   docker exec openelisglobal-database psql -U clinlims clinlims -c "DELETE FROM clinlims.analyzer_bridge_pairing"
   ```

   Within 30 seconds OpenELIS pairs with the new bridge; Admin > Analyzers
   then shows "Paired" with a new bridge certificate. Results analyzers send
   meanwhile wait in the bridge and are delivered once paired.
5. Check:
   - The site opens over HTTPS with no certificate warning.
   - Log in; the banner, site name and menus are as before.
   - Recent orders and results are there; patient search finds a known patient.
   - Admin > Analyzers shows the bridge as paired and lists the analyzers.
6. Tidy the host: scheduled jobs that still point at the old folder or
   patch the database directly (backups, boot-time scripts, a cron running
   `scripts/generate-letsencrypt-certs.sh` when a host certbot owns the
   certificate). Point backups at `sudo ./scripts/backup.sh`. A host
   certbot's deploy hook keeps working: the proxy container keeps its name,
   `openelisglobal-proxy`.

## Going back

```bash
cd /srv/openelis-distro-png && docker compose down
cd /srv/openelis-docker && docker compose up -d
```

The old stack starts on its untouched data, with the newest `:develop`
images (the pull above updated the tags). Anything entered on this stack
since the cutover is not carried back. `data/` is kept for inspection.

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
