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
# Internal TLS is this site's own: the certificate is generated here the first
# time (it is not the shared one the certgen image ships), and the stores are
# rebuilt whenever they do not open with the .env passwords or are older than
# the certificate. Browsers never see it; they get the proxy's Let's Encrypt
# certificate.
set -euo pipefail

: "${KEYSTORE_PW:?set SSL_KEYSTORE_PASSWORD in .env}"
: "${TRUSTSTORE_PW:?set SSL_TRUSTSTORE_PASSWORD in .env}"
export KEYSTORE_PW TRUSTSTORE_PW
WEBAPP_UID="${WEBAPP_UID:-8443}"
BRIDGE_UID="${BRIDGE_UID:-9257}"
TLS_SUBJECT="${TLS_SUBJECT:-/O=OpenELIS Global/CN=oe.openelis.org}"
D=/data

log() { echo "init: $*"; }

# --- directory tree and owners ---------------------------------------------
mkdir -p "$D/db" "$D/bridge" "$D/analyzer-imports" \
    "$D/webapp/lucene" "$D/webapp/properties" "$D/webapp/branding" \
    "$D/webapp/nce-attachments" "$D/webapp/reporting" \
    "$D/logs/oe" "$D/logs/tomcat" \
    "$D/tls/certs" "$D/tls/keys" "$D/tls/stores"

chown -R "$WEBAPP_UID" "$D/webapp" "$D/logs"
chmod 750 "$D/webapp/properties"
chown -R "$BRIDGE_UID:$BRIDGE_UID" "$D/bridge" "$D/analyzer-imports"
chmod 750 "$D/bridge"

# --- this site's certificate -----------------------------------------------
CERT="$D/tls/certs/apache-selfsigned.crt"
KEY="$D/tls/keys/apache-selfsigned.key"
if [ ! -s "$CERT" ] || [ ! -s "$KEY" ]; then
    log "generating this site's internal certificate ($TLS_SUBJECT)"
    openssl req -x509 -nodes -days 3650 -newkey rsa:3072 \
        -keyout "$KEY" -out "$CERT" -subj "$TLS_SUBJECT" \
        -addext "subjectAltName=DNS:*.openelis.org,DNS:oe.openelis.org,DNS:fhir.openelis.org,DNS:bridge.openelis.org,DNS:openelisglobal-webapp,DNS:localhost"
fi
chmod 700 "$D/tls/keys"
chmod 600 "$KEY"
chmod 644 "$CERT"

# --- keystores -------------------------------------------------------------
S="$D/tls/stores"
opens_with() { keytool -list -storetype pkcs12 -keystore "$1" -storepass:env "$2" >/dev/null 2>&1; }

if [ -s "$S/keystore" ] && [ -s "$S/client_facing_keystore" ] \
    && [ ! "$CERT" -nt "$S/keystore" ] \
    && opens_with "$S/keystore" KEYSTORE_PW && opens_with "$S/client_facing_keystore" KEYSTORE_PW; then
    log "keystore is current"
else
    log "building the keystore"
    openssl pkcs12 -export -name oe -inkey "$KEY" -in "$CERT" -out "$S/keystore.new" -passout env:KEYSTORE_PW
    mv "$S/keystore.new" "$S/keystore"
    cp "$S/keystore" "$S/client_facing_keystore"
fi

if [ -s "$S/truststore" ] && [ ! "$CERT" -nt "$S/truststore" ] && opens_with "$S/truststore" TRUSTSTORE_PW; then
    log "truststore is current"
else
    log "building the truststore"
    rm -f "$S/truststore.new"
    keytool -import -noprompt -alias oeCert -file "$CERT" -storetype pkcs12 \
        -keystore "$S/truststore.new" -storepass:env TRUSTSTORE_PW
    mv "$S/truststore.new" "$S/truststore"
fi
# Password-protected; read by the webapp (8443), FHIR and the Bridge (9257).
chmod 644 "$S/keystore" "$S/client_facing_keystore" "$S/truststore"

log "data tree ready"
