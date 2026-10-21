#!/bin/sh
# Runs before the database or application can start, including plain Compose up.
set -eu
. /scripts/password-policy.sh
validate_admin_password "${OE_ADMIN_PASSWORD:-}"
[ -n "${OE_DB_PASSWORD:-}" ] && [ "$OE_DB_PASSWORD" != clinlims ] || {
    echo 'Set a unique OE_DB_PASSWORD in .env.' >&2; exit 1;
}
[ -n "${ADMIN_PASSWORD:-}" ] && [ "$ADMIN_PASSWORD" != superuser ] && [ "$ADMIN_PASSWORD" != admin ] || {
    echo 'Set a unique ADMIN_PASSWORD in .env.' >&2; exit 1;
}
# Preserve the host operator's group while allowing application checksums.
chown -R 8443 /configuration
chmod -R u+rwX,g+rwX,o+rX /configuration
find /configuration -type d -exec chmod g+s {} +
exec /bin/sh /scripts/init-security.sh
