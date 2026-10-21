#!/bin/sh
. /usr/local/tomcat/bin/png-quiet-startup.sh

# Read as the application user before Spring resolves common.properties.
# Retain this secret with the database; it is independent of TLS passwords.
if [ ! -r /etc/openelis-global/encryption.key ]; then
    echo "PNG encryption secret is missing or unreadable; refusing startup." >&2
    exit 1
fi
OE_ENCRYPTION_PASSWORD=$(cat /etc/openelis-global/encryption.key)
if [ "${#OE_ENCRYPTION_PASSWORD}" -ne 64 ]; then
    echo "PNG encryption secret is invalid; refusing startup." >&2
    exit 1
fi
export OE_ENCRYPTION_PASSWORD
