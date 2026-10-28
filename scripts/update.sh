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
umask 077

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
        docker compose exec -T db.openelis.org pg_dump -U clinlims -d clinlims -Fc --no-acl > "$DEST/clinlims.dump"
        [ "$(wc -c < "$DEST/clinlims.dump")" -gt 1024 ] || die "database dump looks empty: $DEST/clinlims.dump"
        log "  $(du -h "$DEST/clinlims.dump" | cut -f1)  $DEST/clinlims.dump"
    else
        die "database is not running; no update performed because a backup is required"
    fi
fi

# --- 3. remember the running images -----------------------------------------
: > "$DEST/images-before.txt"
# Inspect deployed containers, not the new checkout's desired image references.
for cid in $(docker compose ps -a -q); do
    image="$(docker inspect -f '{{.Config.Image}}' "$cid")"
    id="$(docker inspect -f '{{.Image}}' "$cid")"
    service="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$cid")"
    docker tag "$id" "local/png-rollback-${service//./-}:pre-update-${STAMP}"
    printf '%s %s %s\n' "$service" "$image" "$id" >> "$DEST/images-before.txt"
done
[ -s "$DEST/images-before.txt" ] || die "no deployed images found; use docker compose up for a fresh install"

# --- 4. pull and restart ----------------------------------------------------
log "pulling images..."
docker compose pull --quiet
log "restarting changed services..."
docker compose up -d

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
while read -r service image old; do
    cid="$(docker compose ps -a -q "$service")"
    new="$(docker inspect -f '{{.Image}}' "$cid" 2>/dev/null || true)"
    if [ "$new" != "$old" ]; then changed=$((changed + 1)); log "  updated: $service"; fi
done < "$DEST/images-before.txt"
log "done: webapp healthy, ${changed} image(s) updated. Backup and image list: $DEST"
if [ "$DO_BACKUP" -eq 1 ]; then
    log "rollback requires $DEST/clinlims.dump plus the matching configuration and security backup."
else
    log "No database backup was requested. Use a verified matching backup before rollback."
fi
log "          images-before.txt records their exact references and local IDs; digest pins must not be retagged."
log "          Run docker compose up -d after restoring the coherent previous pins."
