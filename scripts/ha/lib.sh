#!/usr/bin/env bash
# Shared helpers for scripts/ha/*. Sourced, not run.
set -euo pipefail

HA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$HA_ROOT"

log() { echo "[ha $(date -u +%H:%M:%S)] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
trap 'echo "ERROR: $(basename "$0") stopped at line $LINENO (exit $?). Fix the cause and re-run it; the scripts are safe to re-run." >&2' ERR

[ "$(id -u)" -eq 0 ] || die "run as root: sudo $0 $*"
[ -f .env ] || die "no .env in $HA_ROOT"
set -a; . ./.env; set +a

need() { [ -n "${!1:-}" ] || die "$1 is not set in .env (see scripts/ha/README.md)"; }
need HA_NODE; need HA_MEMBERS; need HA_REPLICATION_PASSWORD; need HA_PG_BIND_WG
case ":${COMPOSE_FILE:-}:" in
  *compose.ha.yaml*) ;;
  *) die "COMPOSE_FILE in .env must include compose.ha.yaml (e.g. COMPOSE_FILE=docker-compose.yml:compose.ha.yaml)";;
esac

DB=db.openelis.org
WEBAPP_CONTAINER=openelisglobal-webapp
HA_STATE_DIR="$HA_ROOT/configs/ha"
mkdir -p "$HA_STATE_DIR"

dc() { docker compose "$@"; }
db_running() { dc ps --status running --services 2>/dev/null | grep -qx "$DB"; }
psql_su() { dc exec -T "$DB" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d "${PGDB:-postgres}" "$@"; }
q() { psql_su -At -c "$1"; }
in_recovery() { q "SELECT pg_is_in_recovery()"; }

data_dir() {
  local d="${DB_VOLUME_MOUNT:-./configs/database/data}"
  case "$d" in /*) echo "$d";; *) echo "$HA_ROOT/${d#./}";; esac
}

db_image() {
  docker compose config --format json | python3 -c 'import json,sys; print(json.load(sys.stdin)["services"]["db.openelis.org"]["image"])'
}

# Run a PostgreSQL client tool from the DB image with the data directory mounted
# and host networking (so it reaches peers over the LAN or the WireGuard tunnel).
pg_tool() {
  local tool=$1; shift
  docker run --rm --network host --user 999:999 \
    -e PGPASSWORD="$HA_REPLICATION_PASSWORD" -e PGCONNECT_TIMEOUT=10 \
    -v "$(data_dir)":/var/lib/postgresql/data \
    --entrypoint "$tool" "$(db_image)" "$@"
}

member_names() { for m in $HA_MEMBERS; do echo "${m%%=*}"; done; }
member_ips() { for m in $HA_MEMBERS; do echo "${m#*=}" | tr ',' '\n'; done; }
member_ips_of() { for m in $HA_MEMBERS; do [ "${m%%=*}" = "$1" ] && echo "${m#*=}" | tr ',' '\n'; done; }

wait_db() {
  for _ in $(seq 1 90); do dc exec -T "$DB" pg_isready -q -U postgres 2>/dev/null && return 0; sleep 2; done
  die "database did not become ready"
}

# Physical replication slots, one per other cluster member. Slots are not
# replicated, so every server that becomes primary must (re)create them.
ensure_slots() {
  local n
  for n in $(member_names); do
    [ "$n" = "$HA_NODE" ] && continue
    if [ "$(q "SELECT count(*) FROM pg_replication_slots WHERE slot_name='ha_$n'")" = 0 ]; then
      q "SELECT pg_create_physical_replication_slot('ha_$n', true)" >/dev/null
      log "created replication slot ha_$n"
    fi
  done
}

# Ask a peer (as the replicator role, over the replication protocol) whether it
# is a primary and which timeline it is on. Prints "primary <tli>", "standby <tli>"
# or "down".
peer_state() {
  local host=$1 out
  out=$(docker run --rm --network host -e PGPASSWORD="$HA_REPLICATION_PASSWORD" -e PGCONNECT_TIMEOUT=5 \
          --entrypoint psql "$(db_image)" -X -At \
          "host=$host port=5432 user=replicator dbname=postgres" \
          -c "SELECT CASE WHEN pg_is_in_recovery() THEN 'standby' ELSE 'primary' END" 2>/dev/null) || { echo down; return; }
  local tli
  tli=$(docker run --rm --network host -e PGPASSWORD="$HA_REPLICATION_PASSWORD" -e PGCONNECT_TIMEOUT=5 \
          --entrypoint psql "$(db_image)" -X -At \
          "host=$host port=5432 user=replicator replication=true" -c "IDENTIFY_SYSTEM" 2>/dev/null | cut -d'|' -f2)
  echo "$out ${tli:-?}"
}

local_timeline() {
  dc exec -T "$DB" psql -X -At -U postgres "dbname=postgres replication=true" -c "IDENTIFY_SYSTEM" | cut -d'|' -f2
}

webapp_wait_healthy() {
  local s
  for _ in $(seq 1 90); do
    s=$(docker inspect -f '{{.State.Health.Status}}' "${1:-$WEBAPP_CONTAINER}" 2>/dev/null || echo missing)
    [ "$s" = healthy ] && { log "webapp healthy"; return 0; }
    sleep 10
  done
  die "webapp not healthy after 15 minutes (last status: $s)"
}

# Rebuild the Lucene search index (it lives in a Docker volume, not in the
# database, so a promoted standby or a fresh snapshot starts without it).
reindex() {
  local c=${1:-$WEBAPP_CONTAINER} base=https://localhost:8443/OpenELIS-Global code
  docker exec "$c" sh -c "rm -f /tmp/ha.jar; curl -k -s -o /dev/null -c /tmp/ha.jar -X POST '$base/ValidateLogin?apiCall=true' \
      --data-urlencode loginName=admin --data-urlencode \"password=\$0\"" "$OE_ADMIN_PASSWORD"
  code=$(docker exec "$c" sh -c "curl -k -s -o /tmp/ha.out -w '%{http_code}' -b /tmp/ha.jar '$base/rest/reindex'; rm -f /tmp/ha.jar")
  if [ "$code" = 200 ]; then log "search index rebuild started"; else log "WARNING: reindex returned HTTP $code; run Admin > reindex by hand"; fi
}

# OpenELIS records which configuration CSVs it has already loaded in
# configs/configuration/backend/<domain>-checksums.properties (SHA-256 per file).
# Those files live on the primary's disk, not in the database, so a standby
# does not have them and its first webapp start after promotion would re-load
# every CSV, overwriting catalog changes made in the UI since. The primary has
# loaded these exact files (all servers run the same release), so record them
# as loaded. Existing checksum files are left alone.
seed_config_checksums() {
  local base="$HA_ROOT/configs/configuration/backend"
  [ -d "$base" ] || return 0
  python3 - "$base" <<'PY'
import hashlib, os, sys
base = sys.argv[1]
for d in sorted(os.listdir(base)):
    p = os.path.join(base, d)
    out = os.path.join(base, d + "-checksums.properties")
    if not os.path.isdir(p) or os.path.exists(out):
        continue
    files = sorted(f for f in os.listdir(p) if os.path.isfile(os.path.join(p, f)) and not f.startswith("."))
    if not files:
        continue
    with open(out, "w") as fh:
        fh.write("#Configuration file checksums - seeded by scripts/ha at promotion\n")
        for f in files:
            fh.write(f"{f}={hashlib.sha256(open(os.path.join(p, f), 'rb').read()).hexdigest()}\n")
    print(f"[ha] seeded {out} ({len(files)} files)")
PY
  chown 8443:8443 "$base"/*-checksums.properties 2>/dev/null || true
}
