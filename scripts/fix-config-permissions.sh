#!/usr/bin/env bash
# Make configs/configuration writable by BOTH the webapp container and the
# host operator. Run once on a fresh clone, before the first
# `docker compose up -d`. Idempotent — safe to re-run any time.
#
# Why this is needed
# ------------------
# ./configs/configuration is bind-mounted at
# /var/lib/openelis-global/configuration inside the webapp, and
# ConfigurationInitializationService writes <domain>-checksums.properties
# straight back into .../configuration/backend/ after each import. Those
# checksums are what let OE skip a re-import when a catalog CSV has not
# changed.
#
# The webapp does NOT run as root: the upstream image creates
# `tomcat_admin` with UID 8443 and drops to it before starting Tomcat
# (Dockerfile: `useradd -M -s /bin/bash -u 8443 tomcat_admin`, entrypoint:
# `exec su tomcat_admin -c ".../catalina.sh run"`). A fresh clone leaves the
# tree owned by the host user, so UID 8443 cannot create the checksum files
# and every boot logs, for all 15 domains:
#
#   Failed to save checksums file: /var/lib/openelis-global/configuration/backend/<domain>-checksums.properties
#
# Nothing is ever recorded, so the entire catalog is re-imported on every
# single restart.
#
# The fix is a split of owner and group:
#
#   owner UID 8443  -> the webapp can write the checksum files
#   group <host>    -> the operator can still edit the catalog CSVs (g+rwX)
#
# A previous version of this script chowned the tree back to the host user
# on the assumption that the webapp ran as root. It did not; that chown
# removed UID 8443's write access and re-created the very fault it was
# meant to repair.
#
# Requires sudo: only root can hand ownership to UID 8443.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${ROOT}/configs/configuration"

# UID of `tomcat_admin` in itechuw/openelis-global-2. Keep in sync with the
# upstream Dockerfile if it ever changes.
WEBAPP_UID="${OE_WEBAPP_UID:-8443}"

# Resolve the operator, not root, when invoked through sudo.
HOST_USER="${SUDO_USER:-${USER:-$(id -un)}}"
HOST_GROUP="$(id -gn "${HOST_USER}")"

if [[ ! -d "${CONFIGURATION}" ]]; then
  echo "Missing ${CONFIGURATION}; nothing to do." >&2
  exit 1
fi

sudo chown -R "${WEBAPP_UID}:${HOST_GROUP}" "${CONFIGURATION}"
sudo chmod -R u+rwX,g+rwX,o+rX "${CONFIGURATION}"

# setgid on the directories, so the checksum files the webapp creates later
# inherit ${HOST_GROUP} rather than the container's `tomcat` group. Without
# it the tree drifts back to mixed ownership after every boot and this
# script has to be re-run to stay tidy.
sudo find "${CONFIGURATION}" -type d -exec chmod g+s {} +

echo "Updated ownership/permissions on ${CONFIGURATION}"
echo "  owner: ${WEBAPP_UID} (tomcat_admin inside the webapp container)"
echo "  group: ${HOST_GROUP} (host operator, ${HOST_USER})"
echo "  mode:  u+rwX,g+rwX,o+rX, g+s on directories"
echo
echo "'ls -l' will show the owner as ${WEBAPP_UID} rather than a name — that"
echo "is expected; UID 8443 exists only inside the container."
