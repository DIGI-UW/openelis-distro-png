#!/usr/bin/env bash
# Turn THIS server into a streaming standby of PRIMARY, copying the whole
# database with pg_basebackup. Use for a brand-new standby, or when
# rejoin.sh cannot rewind.
#   sudo ./scripts/ha/standby-init.sh <primary-address> [--force]
# --force: discard a writable database that is on this server.
. "$(dirname "$0")/lib.sh"
PRIMARY=${1:-}; FORCE=${2:-}
[ -n "$PRIMARY" ] || die "usage: $0 <primary-address> [--force]"

st=$(peer_state "$PRIMARY")
case "$st" in primary*) log "upstream $PRIMARY is a primary (timeline ${st#* })";; *) die "$PRIMARY does not answer as a primary ($st). Check WireGuard/LAN, HA_MEMBERS on the primary, and the replicator password";; esac

if db_running && [ "$(in_recovery)" = f ] && [ "$FORCE" != --force ]; then
  die "this server has a WRITABLE database. If you are sure its data can be discarded, re-run with --force"
fi

log "stopping the stack on this server"
dc down --remove-orphans

DATA="$(data_dir)"
if [ -d "$DATA" ] && [ -n "$(ls -A "$DATA" 2>/dev/null)" ]; then
  OLD="$DATA.pre-standby-$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$DATA" "$OLD"; log "previous data directory kept at $OLD (delete it once the standby is verified)"
fi
mkdir -p "$DATA"; chown 999:999 "$DATA"; chmod 700 "$DATA"

log "pg_basebackup from $PRIMARY (slot ha_$HA_NODE) -- this copies the whole database"
pg_tool pg_basebackup \
  -d "host=$PRIMARY port=5432 user=replicator application_name=$HA_NODE" \
  -D /var/lib/postgresql/data -X stream -c fast -R -S "ha_$HA_NODE" -P -v

log "starting the database only (a standby never runs the webapp)"
dc up -d "$DB"; wait_db
[ "$(in_recovery)" = t ] || die "database did not come up as a standby"
sleep 3
log "wal receiver: $(q "SELECT status||' from '||sender_host FROM pg_stat_wal_receiver")"
date -u > "$HA_STATE_DIR/standby-since"; rm -f "$HA_STATE_DIR/FENCED"
log "standby ready. Check from the primary: sudo ./scripts/ha/status.sh"
