#!/usr/bin/env bash
# Show this server's HA role and replication health.
#   sudo ./scripts/ha/status.sh           # human-readable
#   sudo ./scripts/ha/status.sh --check   # quiet; exit 1 on a problem (for cron/monitoring)
. "$(dirname "$0")/lib.sh"
CHECK=${1:-}; PROBLEMS=()
say() { [ "$CHECK" = --check ] || echo "$*"; }

if [ -f "$HA_STATE_DIR/FENCED" ]; then say "role: FENCED ($(cat "$HA_STATE_DIR/FENCED"))"; exit 0; fi
db_running || { echo "database is not running"; exit 1; }
WEB=$(docker ps -a --filter "name=^/${WEBAPP_CONTAINER}\$" --format '{{.Status}}'); WEB=${WEB:-not running}

if [ "$(in_recovery)" = f ]; then
  say "role: PRIMARY ($HA_NODE)  timeline $(local_timeline)  webapp: $WEB"
  say "standbys:"
  [ "$CHECK" = --check ] || psql_su -c "SELECT application_name AS standby, client_addr, state,
      pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS behind,
      coalesce(replay_lag::text,'-') AS replay_lag FROM pg_stat_replication ORDER BY 1"
  say "slots:"
  [ "$CHECK" = --check ] || psql_su -c "SELECT slot_name, active, wal_status,
      pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_held FROM pg_replication_slots ORDER BY 1"
  while read -r s; do [ -n "$s" ] && PROBLEMS+=("slot $s is not connected"); done < <(q "SELECT slot_name FROM pg_replication_slots WHERE NOT active")
  while read -r s; do [ -n "$s" ] && PROBLEMS+=("standby $s has not replied for over 2 minutes"); done < <(q "SELECT application_name FROM pg_stat_replication WHERE reply_time < now() - interval '2 minutes'")
  while read -r s; do [ -n "$s" ] && PROBLEMS+=("slot $s is holding more than ${HA_ALERT_WAL_HELD:-2GB} of WAL (standby far behind)"); done < <(q "SELECT slot_name FROM pg_replication_slots WHERE pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) > pg_size_bytes('${HA_ALERT_WAL_HELD:-2GB}')")
  while read -r s; do [ -n "$s" ] && PROBLEMS+=("slot $s has lost WAL (standby needs standby-init.sh)"); done < <(q "SELECT slot_name FROM pg_replication_slots WHERE wal_status='lost'")
  case "$WEB" in *"(healthy)"*) ;; *) PROBLEMS+=("webapp is $WEB on the primary");; esac
else
  say "role: STANDBY ($HA_NODE)  timeline $(local_timeline)  webapp: $WEB"
  [ "$CHECK" = --check ] || psql_su -c "SELECT status, sender_host AS upstream, slot_name,
      pg_size_pretty(pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())) AS replay_backlog,
      coalesce((now() - pg_last_xact_replay_timestamp())::text, 'n/a') AS since_last_replayed_txn,
      last_msg_receipt_time FROM pg_stat_wal_receiver"
  [ "$(q "SELECT count(*) FROM pg_stat_wal_receiver WHERE status='streaming'")" = 1 ] || PROBLEMS+=("not streaming from the primary")
  [ "$WEB" = "not running" ] || PROBLEMS+=("webapp container exists on a standby ($WEB); run: docker compose down && docker compose up -d $DB")
fi

if [ ${#PROBLEMS[@]} -gt 0 ]; then printf 'PROBLEM: %s\n' "${PROBLEMS[@]}" >&2; exit 1; fi
say "OK"
