#!/usr/bin/env bash
# Resolve current tags (no arguments), or select OE and Bridge tags, then
# pin every base image including certgen to an immutable registry digest.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$ROOT/scripts/pin-images.py" "$@"
