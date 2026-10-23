#!/usr/bin/env bash
# Rewrite docker-compose.yml image tags to a target release version.
#
# Usage:
#   ./scripts/pin-versions.sh                # no-op, current pins reported
#   ./scripts/pin-versions.sh 3.3.0          # pin every OpenELIS image, the
#                                            # Analyzer Bridge included, to 3.3.0
#   ./scripts/pin-versions.sh develop        # back to develop
#
# The Analyzer Bridge image (itechuw/openelis-global-2-analyzer-bridge) is
# published with the OpenELIS images under the same tags, so it takes the
# OpenELIS version. A second argument is accepted for compatibility and
# ignored.
#
# This script only rewrites the human-readable tag (`repo:tag`); it does
# NOT append `@sha256:<digest>`. Tags like `3.2.1.6` are treated as fixed
# releases by upstream convention. Implementers wanting cryptographic
# pinning can resolve digests at deploy time.
#
# After running, review:  git diff docker-compose.yml  →  commit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

COMPOSE_FILES=(docker-compose.yml docker-compose.analyzers.yml)

# Read the current tag for a given image repo from the compose files' image: lines.
get_current_tag() {
  local repo="$1"
  grep -hE "image:[[:space:]]*${repo}:" "${COMPOSE_FILES[@]}" \
    | head -n1 \
    | sed -E "s|.*${repo}:([^@[:space:]]+).*|\1|"
}

OE_REPOS=(
  itechuw/openelis-global-2
  itechuw/openelis-global-2-frontend
  itechuw/openelis-global-2-database
  itechuw/openelis-global-2-fhir
  itechuw/openelis-global-2-proxy
  itechuw/openelis-global-2-analyzer-bridge
)
CERTGEN_REPO=itechuw/certgen

CUR_OE="$(get_current_tag "${OE_REPOS[0]}")"
OE_VERSION="${1:-${CUR_OE:-develop}}"
CERTGEN_TAG="main"

update_image() {
  local repo="$1" new_tag="$2" file
  for file in "${COMPOSE_FILES[@]}"; do
    sed -i.bak -E "s|(image:[[:space:]]+)${repo}:[^[:space:]]+|\1${repo}:${new_tag}|" "$file"
    rm -f "${file}.bak"
  done
}

for repo in "${OE_REPOS[@]}"; do
  update_image "$repo" "$OE_VERSION"
done
update_image "$CERTGEN_REPO" "$CERTGEN_TAG"

echo "Pinned every OpenELIS image (Analyzer Bridge included) to ${OE_VERSION}."
echo "Review:  git diff ${COMPOSE_FILES[*]}  ->  commit."
