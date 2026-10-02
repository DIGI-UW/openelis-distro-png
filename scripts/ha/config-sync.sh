#!/usr/bin/env bash
# Carry on-disk files the database does not hold to the standbys THROUGH
# replication: the primary stores them in table openelis_ha.files, standbys
# receive the table, and promote.sh writes the files back to disk.
# Default set: OpenELIS's configuration checksum files, which tell the webapp
# which CSVs it has already loaded (without them a promoted standby re-loads
# every CSV on first start). Add more with HA_SYNC_FILES (space-separated globs
# relative to the distro directory).
#   sudo ./scripts/ha/config-sync.sh push      # on the primary (cron every 10 min; no-op on a standby)
#   sudo ./scripts/ha/config-sync.sh restore   # write the stored files to disk (promote.sh does this)
. "$(dirname "$0")/lib.sh"
MODE=${1:-}
GLOBS=${HA_SYNC_FILES:-"configs/configuration/backend/*-checksums.properties"}
db_running || die "database is not running"

case "$MODE" in
push)
  [ "$(in_recovery)" = f ] || exit 0
  # shellcheck disable=SC2086
  python3 - $GLOBS <<'PY' | PGDB=clinlims psql_su
import base64, glob, hashlib, os, sys
print("CREATE SCHEMA IF NOT EXISTS openelis_ha;")
print("CREATE TABLE IF NOT EXISTS openelis_ha.files (path text PRIMARY KEY, content bytea NOT NULL, sha256 text NOT NULL, owner text, updated_at timestamptz DEFAULT now());")
n = 0
for g in sys.argv[1:]:
    for p in sorted(glob.glob(g)):
        if not os.path.isfile(p): continue
        b = open(p, "rb").read(); st = os.stat(p)
        h = hashlib.sha256(b).hexdigest(); e = base64.b64encode(b).decode()
        print(f"INSERT INTO openelis_ha.files(path,content,sha256,owner) VALUES ('{p}', decode('{e}','base64'), '{h}', '{st.st_uid}:{st.st_gid}') "
              f"ON CONFLICT (path) DO UPDATE SET content=EXCLUDED.content, sha256=EXCLUDED.sha256, owner=EXCLUDED.owner, updated_at=now() WHERE openelis_ha.files.sha256 <> EXCLUDED.sha256;")
        n += 1
print(f"SELECT 'pushed {n} file(s)' AS config_sync;")
PY
  ;;
restore)
  [ "$(PGDB=clinlims q "SELECT to_regclass('openelis_ha.files') IS NOT NULL")" = t ] || { log "no stored files (config-sync push never ran on the primary)"; exit 0; }
  PGDB=clinlims q "SELECT path||' '||owner||' '||translate(encode(content,'base64'), E'\\n', '') FROM openelis_ha.files" | python3 -c '
import base64, hashlib, os, sys
for line in sys.stdin:
    path, owner, e = line.rstrip("\n").split(" ", 2)
    b = base64.b64decode(e)
    if os.path.exists(path) and open(path, "rb").read() == b:
        continue
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(b)
    u, g = owner.split(":"); os.chown(path, int(u), int(g))
    print(f"[ha] restored {path}")
'
  ;;
*) die "usage: $0 push|restore";;
esac
