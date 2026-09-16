#!/usr/bin/env bash
# Back up an OpenELIS PNG site: the clinlims database plus the on-disk
# configuration tree.
#
# MUST RUN AS ROOT (sudo). configs/bridge-state is mode 750 owned by
# UID 9257 (the analyzer bridge's `astm` account — see
# scripts/init-bridge-state.sh), and configs/configuration is owned by
# UID 8443 after scripts/fix-config-permissions.sh. A host-user `tar` over
# configs/ therefore hits "Cannot open: Permission denied", exits 2, and
# still leaves a tarball behind — an archive that looks fine and silently
# omits the bridge's SQLite state. This script refuses to run unprivileged
# rather than produce that.
#
# Usage:
#   sudo ./scripts/backup.sh                 # -> ./backups/<timestamp>/
#   sudo ./scripts/backup.sh /srv/oe-backups # explicit destination root
#
# Restore: see docs/backup-restore.md. Read it before restoring — restoring
# as -U postgres will take the site down.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DB_SERVICE='db.openelis.org'
DEST_ROOT="${1:-${ROOT}/backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="${DEST_ROOT}/${STAMP}"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: this script must run as root." >&2
    echo "       configs/bridge-state is 750 9257:9257 and configs/configuration is" >&2
    echo "       owned by UID 8443; an unprivileged tar skips them and still exits" >&2
    echo "       with an archive, so the backup would be quietly incomplete." >&2
    echo "  sudo $0 $*" >&2
    exit 1
fi

compose() { docker compose -f docker-compose.yml "$@"; }

if ! compose ps --status running --services 2>/dev/null | grep -qx "$DB_SERVICE"; then
    echo "ERROR: ${DB_SERVICE} is not running; cannot dump the database." >&2
    exit 1
fi

mkdir -p "$DEST"
echo "[backup] destination: ${DEST}"

# --- database ------------------------------------------------------------
# Custom format (-Fc) so the restore side can use pg_restore's --clean
# --if-exists --no-owner. Dumped as clinlims, the role that owns the
# application schema, which is also the role docs/backup-restore.md
# restores as.
echo "[backup] pg_dump clinlims (custom format)..."
compose exec -T "$DB_SERVICE" \
    pg_dump -U clinlims -d clinlims -Fc --no-owner --no-acl \
    > "${DEST}/clinlims.dump"

DUMP_BYTES="$(stat -c %s "${DEST}/clinlims.dump")"
if [ "$DUMP_BYTES" -lt 1024 ]; then
    echo "ERROR: clinlims.dump is only ${DUMP_BYTES} bytes — the dump failed." >&2
    exit 1
fi
echo "[backup]   clinlims.dump: $(numfmt --to=iec "$DUMP_BYTES" 2>/dev/null || echo "${DUMP_BYTES}B")"

# --- configuration tree ---------------------------------------------------
# Ownership and modes are preserved (--numeric-owner) because they are load
# bearing: UID 8443 must own configs/configuration for the webapp to write
# its checksum files, and UID 9257 must own configs/bridge-state for the
# bridge's SQLite store to open. A restore that flattens them re-creates
# the very faults fix-config-permissions.sh and init-bridge-state.sh exist
# to prevent.
#
# configs/database/data is excluded deliberately: a file-level copy of a
# live PostgreSQL data directory is not a consistent backup. clinlims.dump
# above is the database backup.
echo "[backup] tar configs/ (excluding the live postgres data directory)..."
tar --numeric-owner \
    --exclude='./configs/database/data' \
    --exclude='./configs/logs' \
    -czf "${DEST}/configs.tar.gz" \
    ./configs

# tar exits 2 on a read failure. `set -e` already aborted if that happened,
# so reaching here means every member was read.
echo "[backup]   configs.tar.gz: $(du -h "${DEST}/configs.tar.gz" | cut -f1)"

# Confirm the root-only subtrees really made it in — these are exactly the
# ones an unprivileged tar drops. Each is checked only if it exists on this
# host (configs/bridge-state is created by scripts/init-bridge-state.sh).
tar tzf "${DEST}/configs.tar.gz" > "${DEST}/.members"
for required in configs/bridge-state configs/configuration/backend; do
    [ -d "${ROOT}/${required}" ] || continue
    if ! grep -q "^\./${required}/" "${DEST}/.members"; then
        echo "ERROR: ${required}/ is missing from configs.tar.gz — incomplete backup." >&2
        rm -f "${DEST}/.members"
        exit 1
    fi
    echo "[backup]   verified: ${required}/ is in the archive"
done
rm -f "${DEST}/.members"

# --- .env ----------------------------------------------------------------
# .env holds OE_DB_PASSWORD and OE_ADMIN_PASSWORD. It is copied because a
# restore is useless without it, and it is copied 0600 because of that.
if [ -f .env ]; then
    install -m 0600 .env "${DEST}/env.backup"
    echo "[backup]   env.backup: copied (mode 0600 — contains credentials)"
else
    echo "[backup]   .env: not present, skipped"
fi

# --- manifest ------------------------------------------------------------
{
    echo "site:        $(hostname)"
    echo "taken:       ${STAMP} (UTC)"
    echo "distro ref:  $(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo unknown)"
    echo "images:"
    grep -E '^[[:space:]]+image:' docker-compose.yml | sed 's/^[[:space:]]*/  /'
} > "${DEST}/MANIFEST.txt"

( cd "$DEST" && sha256sum ./* > SHA256SUMS 2>/dev/null || true )

chmod 0700 "$DEST"
echo
echo "[backup] done: ${DEST}"
echo "[backup] This directory contains credentials — it is mode 0700. Keep it that way."
echo "[backup] Restore procedure: docs/backup-restore.md"
