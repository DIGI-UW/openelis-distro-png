#!/usr/bin/env bash
# Set the in-app OpenELIS `admin` password to OE_ADMIN_PASSWORD from .env.
#
# MANDATORY on every new site. Run once, after the first
# `docker compose up -d` has come up healthy.
#
# Why a post-install step
# -----------------------
# The admin account is created on first boot by CreateAdminUserTask, which
# reads a bcrypt hash from adminPassword.txt *on the WAR classpath*. That
# file is generated at image BUILD time from the `DEFAULT_PW` Docker ARG
# (upstream Dockerfile:19 -> install/createDefaultPassword.sh). `DEFAULT_PW`
# is not read at runtime, so the `DEFAULT_PW=${OE_ADMIN_PASSWORD}` line this
# distro used to carry in docker-compose.yml did nothing at all: every site
# went live on the published default admin / adminADMIN! until somebody
# happened to change it in the UI.
#
# A distro that ships pinned upstream images cannot change a build ARG, so
# the password is rotated in the database instead. The hash is produced by
# pgcrypto's bcrypt (`gen_salt('bf', 12)`), which yields the exact
# $2a$12$... form OpenELIS expects (LoginUserServiceImpl.BCRYPT_PATTERN,
# cost 12 matching install/createDefaultPassword.sh `htpasswd -bcBC 12`).
#
# The same value is read by the analyzer bridge
# (ORG_ITECH_AHB_FORWARD_HTTP_SERVER_PASSWORD) to authenticate its REST
# forwards, so .env stays the single source of truth for both.
#
# Usage:
#   ./scripts/set-admin-password.sh              # use OE_ADMIN_PASSWORD from .env
#   ./scripts/set-admin-password.sh --check      # report only, change nothing
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEFAULT_PW='adminADMIN!'
DB_SERVICE='db.openelis.org'
CHECK_ONLY=false

while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=true ;;
        -h|--help) sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

# --- load OE_ADMIN_PASSWORD from .env ------------------------------------
if [ -z "${OE_ADMIN_PASSWORD:-}" ] && [ -f .env ]; then
    # shellcheck disable=SC2046
    OE_ADMIN_PASSWORD="$(sed -n 's/^[[:space:]]*OE_ADMIN_PASSWORD[[:space:]]*=[[:space:]]*//p' .env | tail -n 1)"
    # strip one layer of surrounding quotes, if present
    OE_ADMIN_PASSWORD="${OE_ADMIN_PASSWORD%\"}"; OE_ADMIN_PASSWORD="${OE_ADMIN_PASSWORD#\"}"
    OE_ADMIN_PASSWORD="${OE_ADMIN_PASSWORD%\'}"; OE_ADMIN_PASSWORD="${OE_ADMIN_PASSWORD#\'}"
fi

if [ -z "${OE_ADMIN_PASSWORD:-}" ]; then
    echo "ERROR: OE_ADMIN_PASSWORD is not set in .env or the environment." >&2
    echo "       cp .env.example .env, set a strong OE_ADMIN_PASSWORD, re-run." >&2
    exit 1
fi

# --- enforce OpenELIS's own password policy before we store anything -----
# MinnPasswordValidation (the default; Property.PasswordRequirments is unset
# in this distro): at least 8 characters, drawn ONLY from letters, digits,
# underscore and % $ # ! -- every other character, hyphen included, is
# rejected -- and covering at least 3 of the 4 classes lower / upper /
# digit / special.
policy_error() {
    echo "ERROR: OE_ADMIN_PASSWORD does not satisfy the OpenELIS password policy." >&2
    echo "       $1" >&2
    echo "       Allowed characters: A-Z a-z 0-9 _ % \$ # !" >&2
    echo "       Minimum length 8, and at least 3 of: lowercase, uppercase, digit, special." >&2
    exit 1
}

[ "${#OE_ADMIN_PASSWORD}" -ge 8 ] || policy_error "It is shorter than 8 characters."
case "$OE_ADMIN_PASSWORD" in
    *[!A-Za-z0-9_%\$\#!]*) policy_error "It contains a character outside the allowed set (a hyphen '-' is the usual culprit)." ;;
esac

classes=0
case "$OE_ADMIN_PASSWORD" in *[a-z]*) classes=$((classes + 1)) ;; esac
case "$OE_ADMIN_PASSWORD" in *[A-Z]*) classes=$((classes + 1)) ;; esac
case "$OE_ADMIN_PASSWORD" in *[0-9]*) classes=$((classes + 1)) ;; esac
case "$OE_ADMIN_PASSWORD" in *[%\$\#!]*) classes=$((classes + 1)) ;; esac
[ "$classes" -ge 3 ] || policy_error "It uses only ${classes} of the 4 character classes; 3 are required."

if [ "$OE_ADMIN_PASSWORD" = "$DEFAULT_PW" ]; then
    echo "ERROR: OE_ADMIN_PASSWORD is still the published default (${DEFAULT_PW})." >&2
    echo "       Choose a site-specific password before going live." >&2
    exit 1
fi

# --- the stack has to be up ----------------------------------------------
compose() { docker compose -f docker-compose.yml "$@"; }

if ! compose ps --status running --services 2>/dev/null | grep -qx "$DB_SERVICE"; then
    echo "ERROR: ${DB_SERVICE} is not running. Start the stack first:" >&2
    echo "  docker compose up -d" >&2
    exit 1
fi

# Run as the postgres superuser over the container's local socket: CREATE
# EXTENSION needs superuser, and this avoids depending on how pg_hba is
# configured for the clinlims role. Only an UPDATE is issued against
# clinlims.login_user, so no object ownership changes -- unlike a
# `pg_restore -U postgres`, which docs/backup-restore.md forbids.
psql_db() {
    compose exec -T "$DB_SERVICE" psql -v ON_ERROR_STOP=1 -qtAX -U postgres -d clinlims "$@"
}

admin_rows="$(psql_db -c "SELECT count(*) FROM clinlims.login_user WHERE login_name = 'admin';" | tr -d '[:space:]')"
if [ "$admin_rows" != "1" ]; then
    echo "ERROR: expected exactly one clinlims.login_user row for 'admin', found ${admin_rows}." >&2
    echo "       The webapp creates it on its first successful boot — wait for" >&2
    echo "       'docker compose ps' to report oe.openelis.org healthy, then re-run." >&2
    exit 1
fi

# --- verification helper: OE's own login endpoint ------------------------
# apiCall=true makes CustomAuthenticationFailureHandler answer 401 instead of
# redirecting, so the status code alone is a reliable signal.
login_status() {
    curl -k -s -o /dev/null -w '%{http_code}' \
        -X POST 'https://localhost:8443/OpenELIS-Global/ValidateLogin?apiCall=true' \
        --data-urlencode 'loginName=admin' \
        --data-urlencode "password=$1" \
        --max-time 20 || echo 000
}

if [ "$CHECK_ONLY" = true ]; then
    echo "Configured password: $(  [ "$(login_status "$OE_ADMIN_PASSWORD")" = 200 ] && echo ACCEPTED || echo REJECTED )"
    echo "Default adminADMIN!: $( [ "$(login_status "$DEFAULT_PW")"        = 200 ] && echo ACCEPTED || echo REJECTED )"
    exit 0
fi

# --- rotate ---------------------------------------------------------------
echo "Setting the 'admin' password from OE_ADMIN_PASSWORD..."

# Where does bcrypt live? If the site already has pgcrypto installed, borrow
# it and leave it alone; otherwise install it into a scratch schema and take
# both back out afterwards, so the clinlims schema keeps exactly the object
# set a later pg_dump/pg_restore expects.
PGCRYPTO_SCHEMA="$(psql_db -c \
    "SELECT n.nspname FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'pgcrypto';" \
    | tr -d '[:space:]')"

if [ -n "$PGCRYPTO_SCHEMA" ]; then
    PREEXISTING_PGCRYPTO=true
else
    PREEXISTING_PGCRYPTO=false
    PGCRYPTO_SCHEMA=oe_pwrotate
    psql_db -c "CREATE SCHEMA IF NOT EXISTS oe_pwrotate;" >/dev/null
    psql_db -c "CREATE EXTENSION pgcrypto WITH SCHEMA oe_pwrotate;" >/dev/null
fi

cleanup_pgcrypto() {
    if [ "$PREEXISTING_PGCRYPTO" = false ]; then
        psql_db -c "DROP EXTENSION IF EXISTS pgcrypto; DROP SCHEMA IF EXISTS oe_pwrotate;" >/dev/null 2>&1 || true
    fi
}
trap cleanup_pgcrypto EXIT

# The password reaches psql on stdin, never on a command line or in an
# environment variable, so it cannot surface in `ps` or in the DB container
# log. Quoting is safe without escaping because the policy check above has
# already rejected every character outside [A-Za-z0-9_%$#!] -- quotes and
# backslashes among them.
{
    printf "\\set newpw '%s'\n" "$OE_ADMIN_PASSWORD"
    # Resolve crypt()/gen_salt() wherever pgcrypto actually lives. The table
    # stays schema-qualified, so search_path only affects function lookup.
    printf "SET search_path TO %s, clinlims, public;\n" "$PGCRYPTO_SCHEMA"
    cat <<'SQL'
UPDATE clinlims.login_user
   SET password = crypt(:'newpw', gen_salt('bf', 12)),
       -- CreateAdminUserTask seeds this five years out; keep it there so the
       -- account is not immediately CredentialsExpired, which would also
       -- break the analyzer bridge's REST forwards.
       password_expired_dt = (CURRENT_DATE + INTERVAL '5 years')::date,
       account_locked   = 'N',
       account_disabled = 'N'
 WHERE login_name = 'admin';
SQL
} | psql_db

cleanup_pgcrypto
trap - EXIT

echo "Database updated. Verifying against the live login endpoint..."

new_code="$(login_status "$OE_ADMIN_PASSWORD")"
old_code="$(login_status "$DEFAULT_PW")"

status=0
if [ "$new_code" = "200" ]; then
    echo "  OK      configured OE_ADMIN_PASSWORD is accepted"
else
    echo "  FAILED  configured OE_ADMIN_PASSWORD was rejected (HTTP ${new_code})" >&2
    status=1
fi

if [ "$old_code" != "200" ]; then
    echo "  OK      default 'adminADMIN!' is rejected (HTTP ${old_code})"
else
    echo "  FAILED  default 'adminADMIN!' is still accepted" >&2
    status=1
fi

if [ "$status" -ne 0 ]; then
    echo >&2
    echo "Admin password rotation did not take effect. Do not expose this site." >&2
    exit 1
fi

echo
echo "Done. Restarting the analyzer bridge so it picks up the same credential:"
compose restart openelis-analyzer-bridge >/dev/null
echo "  openelis-analyzer-bridge restarted"
