#!/bin/bash
# Prepare DATA_ROOT for the stack. Runs as root in the `init` service at every
# `docker compose up`, before any other service starts. Idempotent: on a
# prepared tree it only re-asserts ownership and leaves everything else alone.
#
#   /data/db                 Postgres data (the database image owns it itself)
#   /data/bridge             Analyzer Bridge state, UID 9257
#   /data/analyzer-imports   Analyzer FILE imports, UID 9257
#   /data/webapp/...         lucene, properties, branding, nce-attachments, reporting: UID 8443
#   /data/logs/{oe,tomcat}   webapp logs, UID 8443
#   /data/tls/certs|keys     this site's self-signed certificate and key
#   /data/tls/stores         keystore, client_facing_keystore, truststore
#
# Fresh installations create private security material once. Existing or partial
# unrecognized TLS directories require an explicit migration; they are never rotated.
set -euo pipefail

: "${KEYSTORE_PW:?set SSL_KEYSTORE_PASSWORD in .env}"
: "${TRUSTSTORE_PW:?set SSL_TRUSTSTORE_PASSWORD in .env}"
export KEYSTORE_PW TRUSTSTORE_PW
WEBAPP_UID="${WEBAPP_UID:-8443}"
BRIDGE_UID="${BRIDGE_UID:-9257}"
D=${PNG_DATA_ROOT:-/data}
. /scripts/password-policy.sh
validate_admin_password "${OE_ADMIN_PASSWORD:-}"
for name in OE_DB_PASSWORD ADMIN_PASSWORD; do
    value=${!name:-}
    case "$value" in ""|clinlims|superuser|admin) echo "Set a unique $name in .env." >&2; exit 1;; esac
done
unset value

log() { echo "init: $*"; }

# --- directory tree and owners ---------------------------------------------
mkdir -p "$D/db" "$D/bridge" "$D/analyzer-imports" \
    "$D/webapp/lucene" "$D/webapp/properties" "$D/webapp/branding" \
    "$D/webapp/nce-attachments" "$D/webapp/reporting" \
    "$D/logs/oe" "$D/logs/tomcat" \
    "$D/tls/certs" "$D/tls/keys" "$D/tls/stores" "$D/installation"

chown -R "$WEBAPP_UID" "$D/webapp" "$D/logs"
chmod 750 "$D/webapp/properties"
chown -R "$BRIDGE_UID:$BRIDGE_UID" "$D/bridge" "$D/analyzer-imports"
chmod 750 "$D/bridge"

# External metadata is installed into the ordinary configuration tree before
# OpenELIS starts. The installer does not import records or activate standards.
python3 /opt/openelis/prepare-configuration-packages.py \
    --pins /opt/openelis/configuration-packages \
    --cache "$D/webapp/reference-packages" \
    --configuration /opt/openelis/configuration
mkdir -p "$D/webapp/reference-packages"
chown -R "$WEBAPP_UID" "$D/webapp/reference-packages"
# Package-created directories must allow OE2 to persist its usual checksum files.
chown -R "$WEBAPP_UID" /opt/openelis/configuration/backend

# --- private installation identity ------------------------------------------
export PNG_DATA_ROOT="$D"
/scripts/init-security.sh
log "data tree ready"
