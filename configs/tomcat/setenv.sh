#!/bin/sh
. /usr/local/tomcat/bin/png-quiet-startup.sh
# One retained installation key; no fallback to a public store password.
key=/etc/openelis-global/encryption.key
if [ ! -r "$key" ] || ! grep -Eq '^[a-f0-9]{64}$' "$key"; then
    echo 'PNG encryption key missing or invalid; restore it with the database.' >&2
    exit 1
fi
OE_ENCRYPTION_PASSWORD=$(cat "$key")
export OE_ENCRYPTION_PASSWORD
unset key
