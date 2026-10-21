#!/usr/bin/env bash
# Online fresh-target install. Run before exposing the proxy to users.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -f .env ]] || { echo 'Copy .env.example to .env and set site passwords first.' >&2; exit 1; }
chmod 600 .env
./scripts/check-release-pins.sh
./scripts/set-admin-password.sh --validate-only
docker compose config --format json | python3 -c '
import json,sys
services=json.load(sys.stdin)["services"]
env=services["db.openelis.org"]["environment"]
for key, default in [("DB_PASSWORD", "clinlims"), ("DB_SUPERUSER_PASSWORD", "superuser")]:
    if not env.get(key) or env[key] == default:
        sys.exit("Set unique database passwords in .env before installation.")
'
docker compose pull
python3 scripts/check-analyzer-mounts.py
# Dependencies start cert generation and Bridge state initialization.
# Keep browser access closed until the published administrator password is gone.
docker compose up -d --wait --wait-timeout 2100 oe.openelis.org fhir.openelis.org frontend.openelis.org
./scripts/set-admin-password.sh
./scripts/set-admin-password.sh --check
docker compose up -d --wait --wait-timeout 120 proxy
echo 'Stack ready. Configure browser HTTPS and pair the Bridge before acceptance.'
