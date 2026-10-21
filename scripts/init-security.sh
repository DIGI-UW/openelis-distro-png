#!/bin/sh
# Fresh PNG identity only. Never rotate or adopt an existing installation.
set -eu
umask 077
stores=/etc/openelis-global
certs=/etc/ssl/certs
keys=/etc/ssl/private
fail() { echo "PNG security initialization: $*" >&2; exit 1; }
: "${KEYSTORE_PW:?Set SSL_KEYSTORE_PASSWORD}"
: "${TRUSTSTORE_PW:?Set SSL_TRUSTSTORE_PASSWORD}"
[ "${#KEYSTORE_PW}" -ge 6 ] && [ "${#TRUSTSTORE_PW}" -ge 6 ] || fail 'Store passwords must have at least six characters.'

validate() {
    for file in keystore truststore client_facing_keystore encryption.key internal.crt; do
        [ -s "$stores/$file" ] || fail "Missing $file; restore the installation security volume. No keys were regenerated."
    done
    keytool -list -keystore "$stores/keystore" -storepass:env KEYSTORE_PW >/dev/null 2>&1 || fail 'Cannot open keystore; restore its original password.'
    keytool -list -keystore "$stores/truststore" -storepass:env TRUSTSTORE_PW >/dev/null 2>&1 || fail 'Cannot open truststore; restore its original password.'
    [ -s "$certs/png-internal.crt" ] || fail 'Missing proxy trust certificate; restore the certificate volume.'
    for file in "$keys/apache-selfsigned.key" "$certs/apache-selfsigned.crt"; do
        [ -s "$file" ] || [ -L "$file" ] || fail 'Missing proxy certificate/key; restore the proxy volumes.'
    done
    openssl x509 -in "$stores/internal.crt" -checkend 0 -noout >/dev/null || fail 'Internal certificate expired; planned renewal is required.'
}

if [ -f "$stores/png-initialized" ]; then
    validate
    echo 'PNG installation security material retained.'
    exit 0
fi
# Docker image files must never be adopted implicitly. All mounts use nocopy.
[ -z "$(ls -A "$stores")" ] || fail 'Unrecognized or incomplete security volume. Refusing to replace existing keys; use a fresh target or restore its complete security volume.'
[ ! -e "$keys/apache-selfsigned.key" ] && [ ! -e "$certs/apache-selfsigned.crt" ] || fail 'Existing proxy material found; refusing to replace it.'
mkdir "$stores/.initializing"
work="$stores/.initializing"
# A failed first run deliberately leaves .initializing and prevents silent retry
# with another identity. No application starts until this job succeeds.
openssl req -x509 -nodes -newkey rsa:3072 -sha256 -days 825 \
    -keyout "$work/server.key" -out "$work/server.crt" \
    -subj '/CN=oe.openelis.org/O=PNG installation' \
    -addext 'subjectAltName=DNS:oe.openelis.org,DNS:fhir.openelis.org,DNS:bridge.openelis.org,DNS:localhost,IP:127.0.0.1' \
    >/dev/null 2>&1
openssl pkcs12 -export -in "$work/server.crt" -inkey "$work/server.key" \
    -name openelis -keypbe AES-256-CBC -certpbe AES-256-CBC -macalg sha256 \
    -out "$stores/keystore" -passout env:KEYSTORE_PW
keytool -importcert -noprompt -alias png-internal -file "$work/server.crt" \
    -keystore "$stores/truststore" -storetype PKCS12 -storepass:env TRUSTSTORE_PW >/dev/null 2>&1
cp "$stores/keystore" "$stores/client_facing_keystore"
openssl rand -hex 32 > "$stores/encryption.key"
chown 8443 "$stores/encryption.key"
chmod 400 "$stores/encryption.key"
cp "$work/server.crt" "$stores/internal.crt"
cp "$work/server.crt" "$certs/png-internal.crt"
cp "$work/server.crt" "$certs/apache-selfsigned.crt"
cp "$work/server.key" "$keys/apache-selfsigned.key"
# The three Java services share the internal identity. Only those services
# mount these encrypted stores; application mounts are read-only.
chmod 644 "$stores/keystore" "$stores/truststore" "$stores/client_facing_keystore" "$stores/internal.crt" "$certs/"*.crt
chmod 600 "$keys/apache-selfsigned.key"
rm -rf "$work"
validate
printf 'png-security-v1\n' > "$stores/png-initialized"
echo 'Generated private PNG installation identity and independent encryption secret.'
