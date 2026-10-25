#!/bin/sh
# Verify through the live application before Compose exposes the proxy.
set -eu
. /scripts/password-policy.sh
validate_admin_password "${OE_ADMIN_PASSWORD:-}"
login_status() {
    printf '%s' "$1" | curl -s --max-time 20 -o /dev/null -w '%{http_code}' \
        --cacert /etc/openelis-global/internal.crt \
        -X POST 'https://oe.openelis.org:8443/api/OpenELIS-Global/ValidateLogin?apiCall=true' \
        --data-urlencode 'loginName=admin' --data-urlencode 'password@-' || true
}
configured=$(login_status "$OE_ADMIN_PASSWORD")
default=$(login_status 'adminADMIN!')
if [ "$configured" != 200 ] || [ "$default" != 401 ]; then
    echo "Administrator verification failed (configured HTTP $configured; default HTTP $default). Proxy startup is blocked." >&2
    echo 'If the password was changed in the application, update OE_ADMIN_PASSWORD to match. Existing initialized passwords are not reset automatically.' >&2
    exit 1
fi
umask 077
printf 'png-admin-v1\n' > /installation-state/admin-initialized
echo 'Configured administrator accepted; published default rejected. Proxy may start.'
