#!/usr/bin/env bash
# Take THIS server out of service so it can never accept writes alongside a
# promoted standby. Stops and removes every container (removed containers do
# not come back on reboot). Data is left in place for rejoin.sh.
#   sudo ./scripts/ha/fence.sh
. "$(dirname "$0")/lib.sh"
if db_running; then
  log "role before fencing: $( [ "$(in_recovery)" = f ] && echo primary || echo standby ), LSN $(q "SELECT CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() ELSE pg_current_wal_lsn() END")"
fi
if db_running && [ "$(in_recovery)" = f ]; then "$(dirname "$0")/config-sync.sh" push || true; fi
log "stopping the webapp first, then the database (clean shutdown sends the last WAL to standbys)"
dc stop -t 30 oe.openelis.org fhir.openelis.org proxy openelis-analyzer-bridge frontend.openelis.org 2>/dev/null || true
dc stop -t 120 "$DB"
dc down --remove-orphans
echo "fenced $(date -u +%FT%TZ) by $(logname 2>/dev/null || echo root)" > "$HA_STATE_DIR/FENCED"
log "FENCED. Nothing runs here now. To bring it back as a standby: sudo ./scripts/ha/rejoin.sh <new-primary-address>"
