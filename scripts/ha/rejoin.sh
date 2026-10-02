#!/usr/bin/env bash
# Make THIS server a standby of NEW_PRIMARY, reusing its existing data where
# possible (pg_rewind copies only blocks that changed after the timelines
# split). Use after a failover, on the old primary or on any standby that
# was following it. Falls back to a full copy (standby-init.sh) if rewind fails.
#   sudo ./scripts/ha/rejoin.sh <new-primary-address>
. "$(dirname "$0")/lib.sh"
P=${1:-}
[ -n "$P" ] || die "usage: $0 <new-primary-address>"
st=$(peer_state "$P")
[ "${st%% *}" = primary ] || die "$P is not answering as a primary ($st)"

if db_running && [ "$(in_recovery)" = f ]; then
  die "this server's database is still a WRITABLE primary. Fence it first: sudo ./scripts/ha/fence.sh"
fi
log "stopping the stack here"
dc down --remove-orphans

log "pg_rewind from $P"
if pg_tool pg_rewind --target-pgdata=/var/lib/postgresql/data \
     --source-server="host=$P port=5432 user=replicator dbname=postgres application_name=$HA_NODE" \
     --write-recovery-conf --progress; then
  # pg_rewind copied the new primary's config; point this standby at its own slot
  DATA="$(data_dir)"
  sed -i '/^primary_slot_name/d' "$DATA/postgresql.auto.conf"
  echo "primary_slot_name = 'ha_$HA_NODE'" >> "$DATA/postgresql.auto.conf"
  dc up -d "$DB"
  for _ in $(seq 1 30); do
    if dc exec -T "$DB" pg_isready -q -U postgres 2>/dev/null && [ "$(in_recovery)" = t ] \
       && [ "$(q "SELECT count(*) FROM pg_stat_wal_receiver WHERE status='streaming'")" = 1 ]; then
      date -u > "$HA_STATE_DIR/standby-since"; rm -f "$HA_STATE_DIR/FENCED"
      log "rejoined as a standby of $P (streaming)"
      exit 0
    fi
    sleep 3
  done
  log "rewound but the database is not streaming after 90 s (last log lines below); falling back to a full copy"
  docker logs --tail 5 openelisglobal-database 2>&1 | sed 's/^/    /' 
else
  log "pg_rewind failed; falling back to a full copy"
fi
exec "$(dirname "$0")/standby-init.sh" "$P" --force
