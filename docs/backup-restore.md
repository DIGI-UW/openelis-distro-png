# Backup and restore

Covers the two things a site cannot be rebuilt without: the `clinlims`
database and the on-disk `configs/` tree. Both are captured by
`scripts/backup.sh`.

> **Read [Restoring](#restoring) before you restore.** Restoring the dump as
> `-U postgres` leaves every table owned by `postgres` and takes the site
> down. That mistake is recoverable, but only by re-restoring correctly.

## Taking a backup

```bash
sudo ./scripts/backup.sh                  # -> ./backups/<UTC timestamp>/
sudo ./scripts/backup.sh /srv/oe-backups  # explicit destination root
```

Produces:

| File | What it is |
|---|---|
| `clinlims.dump` | `pg_dump -Fc --no-owner --no-acl`, taken as the `clinlims` role |
| `configs.tar.gz` | `configs/` with numeric ownership preserved, minus `configs/database/data` and `configs/logs` |
| `env.backup` | copy of `.env`, mode 0600 — **contains `OE_DB_PASSWORD` and `OE_ADMIN_PASSWORD`** |
| `MANIFEST.txt` | hostname, timestamp, distro ref, resolved image pins |
| `SHA256SUMS` | checksums of the above |

The output directory is mode 0700 because of `env.backup`. Keep it that way,
and treat the backup as credential material wherever you copy it.

### Why it must run as root

`scripts/backup.sh` refuses to run unprivileged, and this is the reason:

```
$ tar -czf configs.tar.gz ./configs          # as the host user
tar: ./configs/bridge-state: Cannot open: Permission denied
tar: Exiting with failure status due to previous errors
$ echo $?
2
```

`configs/bridge-state` is mode `750` owned by UID `9257` — the analyzer
bridge's `astm` account (see `scripts/init-bridge-state.sh`) — and
`configs/configuration` is owned by UID `8443` after
`scripts/fix-config-permissions.sh`. `tar` exits 2 but **still leaves a
tarball behind**, so an unprivileged backup looks like it worked and is
silently missing the bridge's SQLite state store. `scripts/backup.sh` fails
closed instead, and verifies both subtrees are present in the finished
archive.

### What is deliberately not backed up

- `configs/database/data` — a file-level copy of a running PostgreSQL data
  directory is not a consistent backup. `clinlims.dump` is the database
  backup.
- `configs/logs` — runtime logs, not state.

## Restoring

### 1. Restore `configs/` and `.env`

```bash
cd /path/to/openelis-distro-png
docker compose down
sudo tar --numeric-owner -xzf /path/to/backup/configs.tar.gz -C .
cp /path/to/backup/env.backup .env && chmod 600 .env
```

`--numeric-owner` is not optional. UID `8443` must own
`configs/configuration` or the webapp cannot write its checksum files, and
UID `9257` must own `configs/bridge-state` or the bridge's SQLite store will
not open. If you extracted without it, run both repair scripts:

```bash
./scripts/fix-config-permissions.sh
./scripts/init-bridge-state.sh
```

### 2. Bring up the database only

```bash
docker compose up -d db.openelis.org
docker compose ps        # wait for it to report healthy
```

### 3. Restore the dump **as `clinlims`**

```bash
docker compose exec -T db.openelis.org \
  pg_restore -U clinlims -d clinlims --clean --if-exists --no-owner \
  < /path/to/backup/clinlims.dump
```

### 4. Start the rest of the stack

```bash
docker compose up -d
docker compose ps        # oe.openelis.org must report healthy
./scripts/set-admin-password.sh --check   # confirm the admin credential
```

## Expected `pg_restore` noise

A correct restore **exits 1** and prints roughly 150 errors. This is normal
and the restore is complete. They all look like this:

```
pg_restore: error: could not execute query: ERROR:  must be owner of function tablefunc_crosstab_2
pg_restore: error: could not execute query: ERROR:  must be owner of type public.tablefunc_crosstab_2
pg_restore: error: could not execute query: ERROR:  must be owner of large object 16456
```

They come from extension-owned objects in `public` (the `tablefunc`
extension and its large objects) that belong to `postgres`, not to
`clinlims`. `--clean` asks `clinlims` to drop them, `clinlims` is not their
owner, and each refusal is counted as an error. Nothing in the `clinlims`
schema — the application's actual data — is affected.

Two ways to deal with it, in order of preference:

**Restrict the restore to the application schema.** This is the quieter
option: `public` holds only extension objects here, so there is nothing to
restore in it.

```bash
docker compose exec -T db.openelis.org \
  pg_restore -U clinlims -d clinlims --clean --if-exists --no-owner -n clinlims \
  < /path/to/backup/clinlims.dump
```

Verify afterwards rather than trusting the exit code:

```bash
# expect ~ the same counts as the source site
docker compose exec -T db.openelis.org psql -U clinlims -d clinlims -c \
  "SELECT count(*) FROM clinlims.sample;"
docker compose exec -T db.openelis.org psql -U clinlims -d clinlims -c \
  "SELECT login_name, is_admin FROM clinlims.login_user;"
```

**Or accept the noise.** If you restore the whole dump, check that every
error names `must be owner of` and a `public.tablefunc_*` object or a large
object, and that nothing names a `clinlims.*` table:

```bash
pg_restore ... 2>&1 | grep -v 'must be owner of' | grep '^pg_restore: error'
```

That filter should print nothing. If it prints anything mentioning a
`clinlims` object, the restore is genuinely broken — do not put the site
into service.

## Never restore as `-U postgres`

```bash
# DO NOT DO THIS
pg_restore -U postgres -d clinlims --clean --if-exists --no-owner < clinlims.dump
```

It looks better, because it exits 0 with no ownership errors. What it
actually does is make `postgres` the owner of every restored table:
`--no-owner` means "assign ownership to the connecting role", and the
connecting role is `postgres`.

The webapp connects as `clinlims`, so the site comes back up and then fails
on the first query:

```
ERROR: permission denied for schema clinlims
```

The stack may even report healthy for a moment before the webapp context
gives up. Recovery is to re-restore correctly as `clinlims` per
[step 3](#3-restore-the-dump-as-clinlims); there is no partial fix worth
attempting.

## Restoring onto a different host

The distro is a versioned artifact, so check out the same tag the backup was
taken from before restoring — `MANIFEST.txt` records the distro ref and the
resolved image digests:

```bash
grep -A10 'distro ref' /path/to/backup/MANIFEST.txt
git clone --branch <ref> https://github.com/DIGI-UW/openelis-distro-png
```

Then follow [Restoring](#restoring) from step 1.
