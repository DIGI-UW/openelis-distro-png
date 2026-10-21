#!/bin/sh
# Set the fresh database's admin password once. Never reset it on ordinary up.
set -eu
. /scripts/password-policy.sh
validate_admin_password "${OE_ADMIN_PASSWORD:-}"
if [ -f /installation-state/admin-initialized ]; then
    echo 'Administrator already initialized; retaining its password.'
    exit 0
fi
psql_db() { psql -v ON_ERROR_STOP=1 -qtAX "$@"; }
rows=$(psql_db -c "SELECT count(*) FROM clinlims.login_user WHERE login_name = 'admin';")
[ "$rows" = 1 ] || { echo 'Expected one initialized administrator account.' >&2; exit 1; }
# Retain the standard extension in the target database; no schema cleanup or
# removal is performed. Reuse its existing namespace if already installed.
psql_db -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto;' >/dev/null
crypto_schema=$(psql_db -c "SELECT quote_ident(n.nspname) FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'pgcrypto';")
# The shared policy excludes quotes and backslashes. Send the password on
# stdin; never interpolate it into a process argument or print it to the log.
{
    printf "\\set newpw '%s'\n" "$OE_ADMIN_PASSWORD"
    printf 'SET search_path TO %s, clinlims, public;\n' "$crypto_schema"
    cat <<'SQL'
UPDATE clinlims.login_user
SET password = crypt(:'newpw', gen_salt('bf', 12)),
    password_expired_dt = (CURRENT_DATE + INTERVAL '5 years')::date,
    account_locked = 'N', account_disabled = 'N'
WHERE login_name = 'admin';
SQL
} | psql_db
echo 'Fresh administrator password set; live verification must pass before proxy startup.'
