# scripts/ha: PostgreSQL streaming-replication failover for openelis-distro-png

Full procedure and checklists: Confluence, OpenELIS Global > "Setup High Availability Fail Over".

One primary runs OpenELIS; standbys run only the database and follow it.
Never two writable servers: fence the old primary before promoting.

| Script | Run on |
|---|---|
| `primary-init.sh [--restart]` | primary: replicator role, WAL settings, pg_hba, slots |
| `standby-init.sh <primary>` | new standby: full copy, start DB only |
| `status.sh [--check]` | any: role, lag, slots (`--check` exits 1 on a problem) |
| `fence.sh` | old primary: stop and remove all containers |
| `promote.sh [--force] [--db-only]` | standby: promote and start OpenELIS (re-runnable) |
| `rejoin.sh <new primary>` | old primary / other standbys: pg_rewind, follow, fall back to full copy |
| `config-sync.sh push\|restore` | primary cron (push) / promote (restore): config checksum files via the DB |
| `install-guard.sh` | all: boot + 2-minute split-brain guard, Docker-after-WireGuard |
| `snapshot-refresh.sh [--stop]` | VPS: nightly do-not-enter-data copy on port 9443 |

Required in `.env` (identical passwords on every server):

```dotenv
COMPOSE_FILE=docker-compose.yml:compose.ha.yaml
HA_NODE=local
HA_MEMBERS="vps=10.88.0.1 local=10.88.0.2,192.168.1.10 local2=10.88.0.3,192.168.1.11"
HA_PG_BIND_WG=10.88.0.2
HA_PG_BIND_LAN=192.168.1.10
HA_REPLICATION_PASSWORD=change-me
# optional: HA_MAX_SLOT_WAL_KEEP=20GB HA_ALERT_WAL_HELD=2GB HA_SNAPSHOT_PORT=9443 HA_SNAPSHOT_DIR=/srv/oe-snapshot HA_SYNC_FILES="..."
```
