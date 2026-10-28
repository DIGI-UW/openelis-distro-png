#!/usr/bin/env bash
# Back up the database, configuration, DATA_ROOT and credentials. Run as root.
# Writers are stopped for the snapshot and the previously running services are
# restarted even if an archive fails. No live PostgreSQL files are copied.
# Usage: sudo ./scripts/backup.sh [destination-root]
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DB_SERVICE='db.openelis.org'
DEST_ROOT="${1:-${ROOT}/backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="${DEST_ROOT}/${STAMP}"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: this script must run as root." >&2
    echo "       DATA_ROOT/bridge is 750 9257:9257 and configs/configuration is" >&2
    echo "       owned by UID 8443; an unprivileged tar skips them and still exits" >&2
    echo "       with an archive, so the backup would be quietly incomplete." >&2
    echo "  sudo $0 $*" >&2
    exit 1
fi

# COMPOSE_FILE and DATA_ROOT come from .env, as for every docker compose call.
compose() { docker compose "$@"; }
# Let Compose resolve .env quoting, defaults and environment overrides.
DATA_ROOT="$(compose config --format json | python3 -c 'import json,sys; c=json.load(sys.stdin); print(next(v["source"] for v in c["services"]["init"]["volumes"] if v["target"] == "/data"))')"
[ -d "$DATA_ROOT" ] || { echo "ERROR: data directory does not exist." >&2; exit 1; }

running="$(compose ps --status running --services)"
if ! printf '%s\n' "$running" | grep -qx "$DB_SERVICE"; then
    echo "ERROR: ${DB_SERVICE} is not running; cannot dump the database." >&2
    exit 1
fi

mkdir -p "$DEST_ROOT"
mkdir -m 0700 "$DEST"
echo "[backup] destination: ${DEST}"
# Back up all stores from the same quiesced application state.
mapfile -t writers < <(printf '%s\n' "$running" | grep -vx "$DB_SERVICE" || true)
resume() {
    result=$?
    trap - EXIT
    if [ "${#writers[@]}" -gt 0 ]; then
        compose start "${writers[@]}" || result=1
    fi
    exit "$result"
}
trap resume EXIT
if [ "${#writers[@]}" -gt 0 ]; then
    echo '[backup] stopping application writers for a consistent snapshot...'
    compose stop "${writers[@]}"
fi


# --- database ------------------------------------------------------------
# Preserve object ownership so a privileged restore can recreate legacy C
# functions while returning application tables to the clinlims role.
echo "[backup] pg_dump clinlims (custom format)..."
compose exec -T "$DB_SERVICE" \
    pg_dump -U clinlims -d clinlims -Fc --no-acl \
    > "${DEST}/clinlims.dump"

DUMP_BYTES="$(wc -c < "${DEST}/clinlims.dump")"
if [ "$DUMP_BYTES" -lt 1024 ]; then
    echo "ERROR: clinlims.dump is only ${DUMP_BYTES} bytes — the dump failed." >&2
    exit 1
fi
echo "[backup]   clinlims.dump: $(numfmt --to=iec "$DUMP_BYTES" 2>/dev/null || echo "${DUMP_BYTES}B")"

# Separate archives make restore destinations explicit even for absolute DATA_ROOT.
tar --numeric-owner --exclude='./configs/database/data' --exclude='./configs/logs' \
    -czf "${DEST}/configs.tar.gz" ./configs
tar --numeric-owner --exclude='./db' --exclude='./logs' \
    -C "$DATA_ROOT" -czf "${DEST}/data.tar.gz" .
printf '%s\n' "$DATA_ROOT" > "${DEST}/data-root.txt"
# Validate archive readability before publishing completion checksums.
tar tzf "${DEST}/configs.tar.gz" > /dev/null
tar tzf "${DEST}/data.tar.gz" > /dev/null

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
    compose config --images 2>/dev/null | sed 's/^/  /'
    echo "image ids:"
    for cid in $(compose ps -a -q); do
        docker inspect -f '{{.Config.Image}} {{.Image}}' "$cid" | sed 's/^/  /'
    done
} > "${DEST}/MANIFEST.txt"

compose config --format json > "${DEST}/compose.backup.json"

( cd "$DEST" && sha256sum clinlims.dump configs.tar.gz data.tar.gz data-root.txt env.backup MANIFEST.txt compose.backup.json > SHA256SUMS )

chmod 0700 "$DEST"
echo
echo "[backup] done: ${DEST}"
echo "[backup] This directory contains credentials — it is mode 0700. Keep it that way."
echo "[backup] Restore configs.tar.gz into the checkout and data.tar.gz into the DATA_ROOT recorded in data-root.txt."
