#!/usr/bin/env bash
# Issue or renew Let's Encrypt certs (HTTP-01) for the distro reverse proxy.
# Prerequisites: openelisglobal-proxy running with ./configs/nginx/certbot mounted and
# nginx serving /.well-known/acme-challenge/ (see configs/nginx/nginx.conf).
#
# Configuration is read from ./.env (the LETSENCRYPT_* block in
# .env.example), which is what .env.example tells you to fill in. A value
# already exported in the environment wins over the .env entry.
#
# Usage:
#   # either fill in the LETSENCRYPT_* block in .env ...
#   ./scripts/generate-letsencrypt-certs.sh --dry-run    # quota-safe validation (no production issuance)
#   ./scripts/generate-letsencrypt-certs.sh              # new cert or renew if due
#
#   # ... or override ad hoc from the shell:
#   LETSENCRYPT_EMAIL='you@example.com' ./scripts/generate-letsencrypt-certs.sh
#
# Settings (from .env or the environment):
#   LETSENCRYPT_EMAIL         required: ACME account / expiry notices
#   LETSENCRYPT_DOMAINS       comma- or space-separated SAN list
#   LETSENCRYPT_DOMAIN        legacy single-domain fallback
#   LETSENCRYPT_PRIMARY_DOMAIN primary domain / default cert name
#   LETSENCRYPT_CERT_NAME     explicit cert lineage name under configs/letsencrypt/live/
#   LETSENCRYPT_STAGING=true  first-time certonly only: real staging CA (untrusted chain)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Read the LETSENCRYPT_* block from .env. Only these keys are consulted and
# .env is never executed, so a stray line in it cannot run anything here.
# An exported value takes precedence, so ad-hoc overrides still work.
env_file_value() {
    [ -f .env ] || return 0
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" .env | tail -n 1 | tr -d '\r'
}

for _le_key in LETSENCRYPT_EMAIL LETSENCRYPT_DOMAINS LETSENCRYPT_DOMAIN \
               LETSENCRYPT_PRIMARY_DOMAIN LETSENCRYPT_CERT_NAME LETSENCRYPT_STAGING; do
    eval "_le_current=\${${_le_key}:-}"
    if [ -z "$_le_current" ]; then
        _le_value="$(env_file_value "$_le_key")"
        # tolerate quoted values in .env
        _le_value="${_le_value%\"}"; _le_value="${_le_value#\"}"
        _le_value="${_le_value%\'}"; _le_value="${_le_value#\'}"
        [ -z "$_le_value" ] || export "$_le_key=$_le_value"
    fi
done
unset _le_key _le_current _le_value

EMAIL="${LETSENCRYPT_EMAIL:-}"
STAGING="${LETSENCRYPT_STAGING:-false}"
DRY_RUN=false
FORCE_RENEW=false

usage() {
    sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            ;;
        --staging)
            STAGING=true
            ;;
        --force-renew)
            FORCE_RENEW=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
    shift
done

mkdir -p ./configs/letsencrypt ./configs/nginx/certbot

# No built-in hostname default: this used to fall back to a Madagascar test
# host, so an unconfigured run would request a certificate for somebody
# else's name (and burn this host's ACME quota doing it).
DOMAINS_INPUT="${LETSENCRYPT_DOMAINS:-${LETSENCRYPT_DOMAIN:-}}"
DOMAINS_INPUT="${DOMAINS_INPUT//,/ }"
read -r -a RAW_DOMAINS <<<"$DOMAINS_INPUT"
if [ "${#RAW_DOMAINS[@]}" -eq 0 ]; then
    echo "ERROR: At least one hostname is required via LETSENCRYPT_DOMAINS (or the legacy LETSENCRYPT_DOMAIN)." >&2
    echo "       Set it in .env — see the LETSENCRYPT_* block in .env.example." >&2
    exit 1
fi

DOMAINS=()
for domain in "${RAW_DOMAINS[@]}"; do
    [ -n "$domain" ] || continue
    skip=false
    for seen in "${DOMAINS[@]}"; do
        if [ "$seen" = "$domain" ]; then
            skip=true
            break
        fi
    done
    [ "$skip" = true ] || DOMAINS+=("$domain")
done

PRIMARY_DOMAIN="${LETSENCRYPT_PRIMARY_DOMAIN:-${DOMAINS[0]}}"
CERT_NAME="${LETSENCRYPT_CERT_NAME:-$PRIMARY_DOMAIN}"

if [ -z "$EMAIL" ]; then
    echo "ERROR: LETSENCRYPT_EMAIL is required" >&2
    echo "       Set it in .env — see the LETSENCRYPT_* block in .env.example —" >&2
    echo "       or pass it inline: LETSENCRYPT_EMAIL='you@example.com' $0" >&2
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q '^openelisglobal-proxy$'; then
    echo "ERROR: Container openelisglobal-proxy must be running (ACME HTTP-01)." >&2
    echo "Start the stack first, e.g. docker compose -f docker-compose.yml up -d proxy" >&2
    exit 1
fi

CERT_PATH="./configs/letsencrypt/live/${CERT_NAME}/fullchain.pem"
RENEWAL_PATH="./configs/letsencrypt/renewal/${CERT_NAME}.conf"

DOMAIN_ARGS=()
for domain in "${DOMAINS[@]}"; do
    DOMAIN_ARGS+=(-d "$domain")
done

current_domains() {
    if [ ! -f "$CERT_PATH" ]; then
        return 1
    fi

    openssl x509 -in "$CERT_PATH" -noout -ext subjectAltName 2>/dev/null \
        | tr ',' '\n' \
        | sed -n 's/.*DNS:\([^[:space:]]*\).*/\1/p' \
        | sed '/^$/d' \
        | sort -u
}

desired_domains() {
    printf '%s\n' "${DOMAINS[@]}" | sed '/^$/d' | sort -u
}

domains_match=false
if [ -f "$CERT_PATH" ]; then
    if [ "$(current_domains)" = "$(desired_domains)" ]; then
        domains_match=true
    fi
fi

run_certbot() {
    docker run --rm \
        -v "$ROOT/configs/letsencrypt:/etc/letsencrypt" \
        -v "$ROOT/configs/nginx/certbot:/var/www/certbot" \
        certbot/certbot:v2.11.0 "$@"
}

echo "Certificate name: ${CERT_NAME}"
echo "Requested hostnames: ${DOMAINS[*]}"

if [ -f "$CERT_PATH" ] && [ "$domains_match" = true ] && [ "$FORCE_RENEW" != true ]; then
    echo "Certificate exists: $CERT_PATH"
    RENEW_ARGS=(renew --non-interactive)
    if [ "$DRY_RUN" = true ]; then
        RENEW_ARGS=(renew --dry-run)
    fi
    echo "Running: certbot ${RENEW_ARGS[*]}"
    run_certbot "${RENEW_ARGS[@]}"
else
    if [ -f "$CERT_PATH" ] || [ -f "$RENEWAL_PATH" ]; then
        echo "Updating existing certificate lineage ${CERT_NAME}..."
    else
        echo "Requesting new certificate for ${CERT_NAME}..."
    fi
    CERTONLY_ARGS=(
        certonly
        --webroot
        --webroot-path=/var/www/certbot
        --cert-name "$CERT_NAME"
        --email "$EMAIL"
        --agree-tos
        --no-eff-email
        --non-interactive
    )
    if [ -f "$CERT_PATH" ] || [ -f "$RENEWAL_PATH" ]; then
        CERTONLY_ARGS+=(--expand)
    fi
    if [ "$FORCE_RENEW" = true ] && [ "$DRY_RUN" != true ]; then
        CERTONLY_ARGS+=(--force-renewal)
    fi
    CERTONLY_ARGS+=("${DOMAIN_ARGS[@]}")
    if [ "$DRY_RUN" = true ]; then
        CERTONLY_ARGS+=(--dry-run)
    fi
    if [ "$STAGING" = true ]; then
        CERTONLY_ARGS+=(--staging)
    fi
    echo "Running: certbot ${CERTONLY_ARGS[*]}"
    run_certbot "${CERTONLY_ARGS[@]}"
fi

echo ""
echo "Next: recreate or restart proxy with the Let's Encrypt overlay so nginx loads certs:"
echo "  docker compose -f docker-compose.yml -f compose.letsencrypt.yaml up -d --force-recreate proxy"
