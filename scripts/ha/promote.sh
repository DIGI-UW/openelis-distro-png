#!/usr/bin/env bash
# Promote THIS standby to primary and start the full OpenELIS stack.
#   sudo ./scripts/ha/promote.sh            # refuses if the old primary still answers
#   sudo ./scripts/ha/promote.sh --force    # you have confirmed the old primary is down/fenced
#   add --db-only to promote the database without starting the webapp
. "$(dirname "$0")/lib.sh"
FORCE=; DBONLY=
for a in "$@"; do case "$a" in --force) FORCE=--force;; --db-only) DBONLY=1;; *) die "unknown option $a";; esac; done
[ -f "$HA_STATE_DIR/FENCED" ] && die "this server is FENCED ($(cat "$HA_STATE_DIR/FENCED")). An old primary must come back with rejoin.sh, never promote.sh"
db_running || { dc up -d "$DB"; wait_db; }
if [ "$(in_recovery)" = f ]; then
  # Re-running after an interrupted promote (e.g. the SSH session dropped):
  # finish the remaining steps instead of failing.
  log "database is already a primary; finishing the remaining promote steps"
  for n in $(member_names); do
    [ "$n" = "$HA_NODE" ] && continue
    for ip in $(member_ips_of "$n"); do
      st=$(peer_state "$ip"); [ "$st" = down ] && continue
      [ "${st%% *}" = primary ] && die "$n ($ip) is ALSO a primary ($st). Stop and decide which server is the real primary before going on."
      break
    done
  done
else

  UP=$(q "SELECT regexp_replace(setting, '.*host=([^ ]+).*', '\1') FROM pg_settings WHERE name='primary_conninfo'")
  st=$(peer_state "$UP")
  if [ "${st%% *}" = primary ] && [ "$FORCE" != --force ]; then
    die "old primary $UP still answers as a PRIMARY. Fence it first (sudo ./scripts/ha/fence.sh on that server). Promoting now would give you two writable databases."
  fi
  # An old primary that is in the middle of shutting down refuses new
  # connections (so it looks "down") while still sending its last WAL.
  # Wait until our WAL receiver has been disconnected for a while.
  for _ in $(seq 1 40); do
    [ "$(q "SELECT count(*) FROM pg_stat_wal_receiver WHERE status='streaming'")" = 0 ] && break
    [ "$FORCE" = --force ] && break
    log "still receiving WAL from $UP; waiting for it to finish (fence it if you have not)"
    sleep 3
  done
  [ "$(q "SELECT count(*) FROM pg_stat_wal_receiver WHERE status='streaming'")" = 0 ] || [ "$FORCE" = --force ] \
    || die "still streaming from $UP after 2 minutes: the old primary is alive. Fence it first."
  log "old primary $UP: $st"
  log "last replayed: $(q "SELECT pg_last_wal_replay_lsn()||' at '||coalesce(pg_last_xact_replay_timestamp()::text,'n/a')")"

  log "promoting"
  [ "$(q "SELECT pg_promote(true, 120)")" = t ] || die "pg_promote failed"
  q "ALTER SYSTEM RESET primary_conninfo" >/dev/null
  q "ALTER SYSTEM RESET primary_slot_name" >/dev/null
  q "SELECT pg_reload_conf()" >/dev/null
fi
# pg_rewind (rejoin.sh on the other servers) reads the timeline from this
# server's control file, which only moves to the new timeline at the next
# checkpoint. Without this, rewinding the old primary right away fails.
q "CHECKPOINT" >/dev/null
log "now primary on timeline $(local_timeline)"
ensure_slots
"$(dirname "$0")/config-sync.sh" restore
seed_config_checksums   # only fills in domains the primary never pushed
rm -f "$HA_STATE_DIR/standby-since" "$HA_STATE_DIR/FENCED"

if docker ps --format '{{.Names}}' | grep -q '^oesnap-'; then
  log "stopping the snapshot copy on this server to free memory and ports"
  "$(dirname "$0")/snapshot-refresh.sh" --stop || true
fi

if [ -n "$DBONLY" ]; then log "DONE (database only). Start OpenELIS later with: docker compose up -d"; exit 0; fi
log "starting the full stack"
dc up -d
webapp_wait_healthy
reindex
log "DONE. Now: point users/DNS/analyzers here, then rejoin the other servers:"
log "  on each other server: sudo ./scripts/ha/rejoin.sh <this server's address>"
