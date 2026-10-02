#!/usr/bin/env bash
# Prepare the CURRENT PRIMARY for streaming replication. Safe to re-run.
#   sudo ./scripts/ha/primary-init.sh            # configure; tells you if a DB restart is pending
#   sudo ./scripts/ha/primary-init.sh --restart  # also restart the database container if needed (~30 s blip)
. "$(dirname "$0")/lib.sh"
RESTART=${1:-}

db_running || die "database is not running (docker compose up -d first)"
[ "$(in_recovery)" = f ] || die "this server is a standby; run primary-init on the primary"

log "replicator role + settings"
psql_su <<SQL
DO \$\$BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'replicator') THEN
    CREATE ROLE replicator WITH LOGIN REPLICATION;
  END IF;
END\$\$;
-- the stock image initialises with md5; store this password as SCRAM so the
-- scram-sha-256 pg_hba lines below can verify it
SET password_encryption = 'scram-sha-256';
ALTER ROLE replicator WITH LOGIN REPLICATION PASSWORD '${HA_REPLICATION_PASSWORD}';
-- lets pg_rewind run as replicator instead of a superuser
GRANT EXECUTE ON FUNCTION pg_catalog.pg_ls_dir(text, boolean, boolean) TO replicator;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_stat_file(text, boolean) TO replicator;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_read_binary_file(text) TO replicator;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_read_binary_file(text, bigint, bigint, boolean) TO replicator;
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET wal_keep_size = '1GB';
-- cap WAL held for a disconnected standby so a dead VPS link cannot fill this disk
ALTER SYSTEM SET max_slot_wal_keep_size = '${HA_MAX_SLOT_WAL_KEEP:-20GB}';
ALTER SYSTEM SET wal_log_hints = on;
ALTER SYSTEM SET hot_standby = on;
SQL

log "pg_hba.conf"
HBA="$(data_dir)/pg_hba.conf"
[ -f "$HBA" ] || die "cannot find $HBA"
cp -p "$HBA" "$HBA.bak-$(date -u +%Y%m%dT%H%M%SZ)"
IPS="$(member_ips | sort -u | tr '\n' ' ')"
python3 - "$HBA" $IPS <<'PY'
import re, sys
path, ips = sys.argv[1], sys.argv[2:]
text = open(path).read()
text = re.sub(r"\n?# BEGIN openelis-ha.*?# END openelis-ha\n?", "\n", text, flags=re.S)
# The stock image accepts password logins for every role from ANY address.
# Once Postgres is published for replication that would expose the superuser,
# so restrict password logins to the stack's own Docker network.
text = re.sub(r"^host\s+all\s+all\s+all\s+(md5|scram-sha-256)\s*$",
              r"host all all 172.20.1.0/24 \1   # restricted by scripts/ha (was: all)",
              text, flags=re.M)
lines = ["# BEGIN openelis-ha (managed by scripts/ha/primary-init.sh; edit HA_MEMBERS in .env)",
         "# 172.20.1.1 = this host itself, reaching the published port through Docker"]
for ip in ["172.20.1.1"] + ips:
    lines.append(f"host replication replicator {ip}/32 scram-sha-256")
    lines.append(f"host postgres    replicator {ip}/32 scram-sha-256")
lines.append("# END openelis-ha")
open(path, "w").write(text.rstrip("\n") + "\n\n" + "\n".join(lines) + "\n")
PY
q "SELECT pg_reload_conf()" >/dev/null
BAD=$(q "SELECT count(*) FROM pg_hba_file_rules WHERE error IS NOT NULL")
[ "$BAD" = 0 ] || die "pg_hba.conf has errors; restore $HBA.bak-* and check"

ensure_slots
"$(dirname "$0")/config-sync.sh" push

PENDING=$(q "SELECT string_agg(name, ', ') FROM pg_settings WHERE pending_restart")
if [ -n "$PENDING" ]; then
  if [ "$RESTART" = --restart ]; then
    log "restarting database for: $PENDING"
    dc restart "$DB"; wait_db
  else
    log "RESTART PENDING for: $PENDING"
    log "re-run with --restart in a quiet moment (the webapp reconnects by itself)"
    exit 0
  fi
fi
log "settings now: $(q "SELECT string_agg(name||'='||setting, ' ') FROM pg_settings WHERE name IN ('wal_level','max_wal_senders','max_replication_slots','wal_log_hints','max_slot_wal_keep_size')")"
log "slots: $(q "SELECT string_agg(slot_name, ' ') FROM pg_replication_slots")"
log "primary ready. Next, on each standby: sudo ./scripts/ha/standby-init.sh <this server's address>"
