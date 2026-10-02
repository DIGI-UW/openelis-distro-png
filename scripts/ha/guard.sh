#!/usr/bin/env bash
# Split-brain guard (systemd service at boot + timer every 2 minutes, installed
# by install-guard.sh). If THIS server is a primary while another cluster
# member is a primary on a NEWER timeline (a failover happened while this
# server was down or cut off), fence this server.
. "$(dirname "$0")/lib.sh"
[ -f "$HA_STATE_DIR/FENCED" ] && exit 0
# at boot, give Docker time to start the database
if [ "$(cut -d. -f1 /proc/uptime)" -lt 600 ]; then
  for _ in $(seq 1 60); do db_running && dc exec -T "$DB" pg_isready -q -U postgres 2>/dev/null && break; sleep 5; done
fi
db_running || exit 0
[ "$(in_recovery)" = f ] || exit 0
MYTLI=$(local_timeline)
for n in $(member_names); do
  [ "$n" = "$HA_NODE" ] && continue
  for ip in $(member_ips_of "$n"); do
    st=$(peer_state "$ip")
    [ "$st" = down ] && continue
    if [ "${st%% *}" = primary ]; then
      tli=${st#* }
      if [ "$tli" != "?" ] && [ "$tli" -gt "$MYTLI" ]; then
        log "SPLIT-BRAIN GUARD: $n ($ip) is primary on timeline $tli > ours ($MYTLI). Fencing this server."
        "$(dirname "$0")/fence.sh"
        exit 0
      fi
      log "$n ($ip) is also primary on timeline $tli (ours $MYTLI) -- investigate"
    fi
    break
  done
done
exit 0
