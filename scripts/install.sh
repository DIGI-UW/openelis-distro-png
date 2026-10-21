#!/usr/bin/env bash
# Optional convenience wrapper; plain docker compose up runs the same safeguards.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -f .env ]] || { echo 'Copy .env.example to .env and set site passwords first.' >&2; exit 1; }
chmod 600 .env
./scripts/check-release-pins.sh
docker compose pull
python3 scripts/check-analyzer-mounts.py
docker compose up -d --wait --wait-timeout 2100
echo 'Stack ready. Configure browser HTTPS and pair the Bridge before acceptance.'
