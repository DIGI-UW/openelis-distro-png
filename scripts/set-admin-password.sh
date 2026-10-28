#!/usr/bin/env bash
# Explicit operator reset; ordinary Compose startup only initializes once.
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
    --check) docker compose run --rm --no-deps verify-admin ;;
    "") docker compose run --rm --no-deps -e PNG_RESET_ADMIN=1 init-admin
        docker compose run --rm --no-deps verify-admin ;;
    *) echo 'Usage: scripts/set-admin-password.sh [--check]' >&2; exit 2 ;;
esac
