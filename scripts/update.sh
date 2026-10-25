#!/usr/bin/env bash
# Update this site to the exact image digests committed in the checkout:
#
#   ./scripts/update.sh              fast-forward this checkout, back up the
#                                    database, pull, restart, wait until healthy
#   ./scripts/update.sh --no-git     leave the checkout alone (restore its pinned images)
#   ./scripts/update.sh --no-backup  skip the database dump (not recommended)
#
# Every update on `develop` can run database migrations that cannot be undone
# by going back to the old images, which is why the dump is taken first. The
# images that were running are tagged <repo>:pre-update-<stamp>; to roll back,
# restore the dump (docs/backup-restore.md) and run those images again (see the
# message printed at the end).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DO_GIT=1; DO_BACKUP=1
for arg in "$@"; do
    case "$arg" in
        --no-git) DO_GIT=0 ;;
        --no-backup) DO_BACKUP=0 ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

log() { echo "[update] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
[ -f .env ] || die "no .env in $ROOT"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="$ROOT/backups/update-${STAMP}"

# --- 1. the checkout --------------------------------------------------------
if [ "$DO_GIT" -eq 1 ]; then
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        log "local changes in tracked files; not pulling (commit or stash them, or use --no-git)"
    elif git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        before="$(git rev-parse --short HEAD)"
        git pull --ff-only --quiet
        log "checkout: ${before} -> $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD))"
    else
        log "checkout has no upstream branch (a release tag?); not pulling"
    fi
fi
docker compose config -q || die "docker compose config failed"

mkdir -p "$DEST"; chmod 0700 "$DEST"

# --- 2. database dump -------------------------------------------------------
if [ "$DO_BACKUP" -eq 1 ]; then
    if docker compose ps --status running --services 2>/dev/null | grep -qx db.openelis.org; then
        log "dumping the database..."
        docker compose exec -T db.openelis.org pg_dump -U clinlims -d clinlims -Fc --no-owner --no-acl > "$DEST/clinlims.dump"
        [ "$(stat -c %s "$DEST/clinlims.dump")" -gt 1024 ] || die "database dump looks empty: $DEST/clinlims.dump"
        log "  $(du -h "$DEST/clinlims.dump" | cut -f1)  $DEST/clinlims.dump"
    else
        log "database is not running; no dump taken"
    fi
fi

# --- 3. remember the running images -----------------------------------------
: > "$DEST/images-before.txt"
for image in $(docker compose config --images | sort -u); do
    id="$(docker image inspect -f '{{.Id}}' "$image" 2>/dev/null || true)"
    [ -n "$id" ] || continue
    # A digest reference is repo@sha256:...; @sha256 is not part of a tag name.
    repository="${image%@*}"
    if [[ "${repository##*/}" == *:* ]]; then repository="${repository%:*}"; fi
    docker tag "$id" "${repository}:pre-update-${STAMP}"
    echo "$image $id" >> "$DEST/images-before.txt"
done

# --- 4. pull and restart ----------------------------------------------------
log "pulling images..."
docker compose pull --quiet
log "restarting changed services..."
docker compose up -d --remove-orphans

# --- 5. wait for the webapp --------------------------------------------------
log "waiting for the webapp to report healthy (first start after a migration can take ~10 min)..."
deadline=$(( $(date +%s) + 1200 ))
while :; do
    cid="$(docker compose ps -q oe.openelis.org)"
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo missing)"
    [ "$status" = healthy ] && break
    [ "$(date +%s)" -lt "$deadline" ] || die "webapp is '$status' after 20 min; check: docker compose logs --tail 200 oe.openelis.org"
    sleep 20
done

changed=0
while read -r image old; do
    new="$(docker image inspect -f '{{.Id}}' "$image" 2>/dev/null || true)"
    if [ "$new" != "$old" ]; then changed=$((changed + 1)); log "  updated: $image"; fi
done < "$DEST/images-before.txt"
log "done: webapp healthy, ${changed} image(s) updated. Backup and image list: $DEST"
log "rollback: restore $DEST/clinlims.dump (docs/backup-restore.md) and the previous Compose image references."
log "          images-before.txt records their exact references and local IDs; digest pins must not be retagged."
log "          Run docker compose up -d after restoring the coherent previous pins."
