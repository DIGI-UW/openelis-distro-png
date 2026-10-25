#!/bin/sh
# Fresh target only. Never infer an old database key or rotate existing identity.
set -eu
umask 077
D=${PNG_DATA_ROOT:-/data}
S="$D/tls/stores"
C="$D/tls/certs"
K="$D/tls/keys"
: "${KEYSTORE_PW:?Set SSL_KEYSTORE_PASSWORD}"
: "${TRUSTSTORE_PW:?Set SSL_TRUSTSTORE_PASSWORD}"
export KEYSTORE_PW TRUSTSTORE_PW
fail() { echo "PNG security initialization: $*" >&2; exit 1; }
[ "${#KEYSTORE_PW}" -ge 6 ] && [ "${#TRUSTSTORE_PW}" -ge 6 ] || fail 'Store passwords must have at least six characters.'
mkdir -p "$S" "$C" "$K"
validate() {
    for f in keystore client_facing_keystore truststore encryption.key internal.crt; do
        [ -s "$S/$f" ] || fail "Missing $f; restore the security directory. No material was regenerated."
    done
    grep -Eq '^[a-f0-9]{64}$' "$S/encryption.key" || fail 'Invalid installation encryption key.'
    for f in keystore client_facing_keystore; do
        keytool -list -storetype PKCS12 -keystore "$S/$f" -storepass:env KEYSTORE_PW >/dev/null 2>&1 || fail "Cannot open $f; restore its original password."
    done
    keytool -list -storetype PKCS12 -keystore "$S/truststore" -storepass:env TRUSTSTORE_PW >/dev/null 2>&1 || fail 'Cannot open truststore; restore its original password.'
    [ -s "$K/apache-selfsigned.key" ] && [ -s "$C/apache-selfsigned.crt" ] || fail 'Missing proxy identity; restore the TLS directory.'
    openssl x509 -in "$S/internal.crt" -checkend 0 -noout >/dev/null || fail 'Internal certificate expired; planned renewal is required.'
    openssl verify -CAfile "$S/internal.crt" -verify_hostname oe.openelis.org "$C/apache-selfsigned.crt" >/dev/null || fail 'Internal certificate mismatch.'
    expected=$(openssl x509 -in "$S/internal.crt" -noout -fingerprint -sha256)
    for f in keystore client_facing_keystore; do
        actual=$(keytool -exportcert -rfc -alias oe -keystore "$S/$f" -storepass:env KEYSTORE_PW 2>/dev/null | openssl x509 -noout -fingerprint -sha256)
        [ "$actual" = "$expected" ] || fail "$f does not contain this installation's certificate."
    done
    actual=$(keytool -exportcert -rfc -alias oeCert -keystore "$S/truststore" -storepass:env TRUSTSTORE_PW 2>/dev/null | openssl x509 -noout -fingerprint -sha256)
    [ "$actual" = "$expected" ] || fail 'Truststore identity mismatch.'
    certificate_public=$(openssl x509 -in "$C/apache-selfsigned.crt" -pubkey -noout | openssl sha256)
    key_public=$(openssl pkey -in "$K/apache-selfsigned.key" -pubout 2>/dev/null | openssl sha256)
    [ "$key_public" = "$certificate_public" ] || fail 'Proxy private key does not match its certificate.'
}
if [ -f "$S/png-initialized" ]; then
    validate
    echo 'PNG private identity and encryption key retained.'
    exit 0
fi
[ -z "$(ls -A "$S")" ] && [ -z "$(ls -A "$C")" ] && [ -z "$(ls -A "$K")" ] || fail 'Unrecognized or partial TLS state. Use an empty fresh target or restore its complete security directory; migration is separate.'
mkdir "$S/.initializing"
# Keep the marker on failure so the next start cannot silently create another key.
openssl req -x509 -nodes -newkey rsa:3072 -sha256 -days 825     -keyout "$K/apache-selfsigned.key" -out "$C/apache-selfsigned.crt"     -subj '/O=OpenELIS PNG/CN=oe.openelis.org'     -addext 'subjectAltName=DNS:oe.openelis.org,DNS:fhir.openelis.org,DNS:localhost,IP:127.0.0.1' >/dev/null 2>&1
openssl pkcs12 -export -name oe -inkey "$K/apache-selfsigned.key" -in "$C/apache-selfsigned.crt"     -out "$S/keystore" -passout env:KEYSTORE_PW
cp "$S/keystore" "$S/client_facing_keystore"
keytool -importcert -noprompt -alias oeCert -file "$C/apache-selfsigned.crt"     -storetype PKCS12 -keystore "$S/truststore" -storepass:env TRUSTSTORE_PW >/dev/null 2>&1
cp "$C/apache-selfsigned.crt" "$S/internal.crt"
openssl rand -hex 32 > "$S/encryption.key"
chown 8443:8443 "$S/keystore" "$S/client_facing_keystore" "$S/truststore" "$S/encryption.key"
chmod 755 "$S" "$C"
chmod 700 "$K"
chmod 640 "$S/keystore" "$S/client_facing_keystore"
chmod 644 "$S/truststore" "$S/internal.crt" "$C/apache-selfsigned.crt"
chmod 400 "$S/encryption.key"
validate
rmdir "$S/.initializing"
printf 'png-security-v2\n' > "$S/png-initialized"
echo 'Generated private PNG identity and a separate encryption key.'
