#!/usr/bin/env bash
# Install the boot-time split-brain guard and make Docker start after WireGuard.
#   sudo ./scripts/ha/install-guard.sh
. "$(dirname "$0")/lib.sh"
cat > /etc/systemd/system/openelis-ha-guard.service <<UNIT
[Unit]
Description=OpenELIS HA split-brain guard
After=docker.service network-online.target wg-quick@wg0.service
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=$HA_ROOT/scripts/ha/guard.sh
TimeoutStartSec=600
[Install]
WantedBy=multi-user.target
UNIT
# Also run every 2 minutes: a primary that was cut off from the network (not
# rebooted) while a standby was promoted must fence itself when it reconnects.
cat > /etc/systemd/system/openelis-ha-guard.timer <<UNIT
[Unit]
Description=OpenELIS HA split-brain guard (periodic)
[Timer]
OnBootSec=3min
OnUnitActiveSec=2min
[Install]
WantedBy=timers.target
UNIT
# Postgres is published on the WireGuard address, so wg0 must exist before Docker starts containers.
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/10-after-wireguard.conf <<UNIT
[Unit]
After=wg-quick@wg0.service
Wants=wg-quick@wg0.service
UNIT
systemctl daemon-reload
systemctl enable openelis-ha-guard.service >/dev/null 2>&1
systemctl enable --now openelis-ha-guard.timer >/dev/null 2>&1
sync
log "installed openelis-ha-guard.service (boot) + .timer (every 2 min) and the docker-after-wireguard drop-in"
