# Backup and restore

Back up the database, installation keys, Bridge state, application files and
configuration together. Keep the backup private: it includes credentials and
may include patient data. A database dump alone is not a complete site backup.

## Take a backup

```bash
sudo ./scripts/backup.sh
# Or choose a destination outside the checkout:
sudo ./scripts/backup.sh /srv/oe-backups
```

Run during a maintenance window. The helper stops this Compose project's running
services except PostgreSQL, takes the snapshot, and restarts those services even
if an archive fails. It does not start services that were already stopped.
The destination is private before any data is written. Require exit status zero
and a complete `SHA256SUMS`; a partial directory is not a completed backup.

| File | Contents |
| --- | --- |
| `clinlims.dump` | Full logical database dump retaining object ownership, without access grants |
| `configs.tar.gz` | Configuration tree, excluding database files and logs |
| `data.tar.gz` | Contents of `DATA_ROOT`, including keys, Bridge state and uploads, excluding live PostgreSQL files and logs |
| `data-root.txt` | Resolved original data-directory path |
| `env.backup` | Private installation settings |
| `compose.backup.json` | Resolved Compose configuration, including credentials and actual paths |
| `MANIFEST.txt` | Distro revision, configured images and deployed container image IDs |
| `SHA256SUMS` | Checksums of the completed backup files |

The data archive has paths relative to `DATA_ROOT`. An absolute data path does
not become a nested host path when extracted. Retain numeric ownership; the
application and Bridge run as different users.

## Restore into an empty replacement installation

Do not run these steps against the active site's database or data directory.
Use a separate host or an isolated Compose project with distinct container names,
network, ports and storage. Select the distro revision and exact images recorded
in the backup. Ensure the original installation remains available for rollback.

1. Verify `sha256sum -c SHA256SUMS` inside the backup directory. Stop on any
   missing or mismatched file.
2. Restore `env.backup` as `.env` with mode `0600`. Review `DATA_ROOT`, host paths,
   ports and Compose overlays for the replacement. The resolved Compose backup
   is evidence of the source configuration; do not start its original host paths
   blindly on the same server.
3. Extract `configs.tar.gz` into the replacement checkout. Create the selected
   empty `DATA_ROOT` and extract `data.tar.gz` directly into it. For example:

   ```bash
   sudo tar --numeric-owner -xzf /path/to/backup/configs.tar.gz -C /path/to/replacement
   sudo mkdir -p /srv/replacement-data
   sudo tar --numeric-owner -xzf /path/to/backup/data.tar.gz -C /srv/replacement-data
   ```

4. Start only PostgreSQL and its initializer:

   ```bash
   docker compose up -d db.openelis.org
   docker compose exec -T db.openelis.org pg_isready -U clinlims -d clinlims
   ```

5. Replace only this new target's initialized database with an empty database
   owned by the application role, then restore with administrator privileges while
   retaining the object ownership recorded in the dump:

   ```bash
   docker compose exec -T db.openelis.org dropdb -U postgres clinlims
   docker compose exec -T db.openelis.org createdb -U postgres -O clinlims -T template0 clinlims
   docker compose exec -T db.openelis.org \
     pg_restore -U postgres -d clinlims --no-acl --exit-on-error \
     < /path/to/backup/clinlims.dump
   ```

   Require a successful restore. Permission errors, missing extensions and large
   object failures are not acceptable noise. Do not start the application after
   a failed restore. This dump retains ownership: application objects return to `clinlims`, while
   administrator-owned functions keep their original owners. The privileged
   restore is needed for older C-language functions. Do not add `--no-owner`: it
   would instead assign every object to `postgres`. Confirm application table
   ownership before starting services.

6. Start the remaining services using ordinary `docker compose up -d`. Verify
   application health, login, clinical record counts, stored encrypted settings,
   Bridge pairing and queued-result delivery where applicable. Confirm private
   keys were retained and public HTTPS works before cutover.

Keep the backup and original installation until acceptance is complete.
A rollback after database migrations restores the matching database, keys and
configuration together; selecting an older application image alone is unsafe.

## Existing databases and older backups

Restoring a backup from this distro retains its encryption key. Moving an older
installation into this distro can require OE2's explicit encrypted-secret
upgrade before the new application starts. That is separate from a fresh install
or ordinary restore. Never generate a replacement key just to make existing
data start, and never delete Bridge pairing or queued data to bypass an error.

Earlier backups used a combined `configs.tar.gz` archive. Inspect their manifest
and archive paths and use the matching distro revision's procedure; do not assume
they contain the separate `data.tar.gz` described here.
