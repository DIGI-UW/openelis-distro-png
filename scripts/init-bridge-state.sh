#!/usr/bin/env bash
# Prepare the bridge state-store host directory before first `docker compose up`.
#
# The analyzer bridge runs as UID 1000 (`astm`) inside the container and writes
# its SQLite state to /data/openelis-analyzer-bridge/state.db. We bind-mount a
# host directory there so the OS perms are under our control; without this the
# bridge fails to boot with:
#   java.sql.SQLException: opening db: '...': Permission denied
#
# Idempotent. Requires sudo for the chown.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${BRIDGE_STATE_HOST_DIR:-${ROOT}/configs/bridge-state}"
BRIDGE_UID="${BRIDGE_UID:-9257}"
BRIDGE_GID="${BRIDGE_GID:-9257}"

mkdir -p "${STATE_DIR}"
sudo chmod 750 "${STATE_DIR}"
sudo chown -R "${BRIDGE_UID}:${BRIDGE_GID}" "${STATE_DIR}"

echo "Bridge state dir ready: ${STATE_DIR}"
echo "  owner: ${BRIDGE_UID}:${BRIDGE_GID}"
echo "  mode:  750"
