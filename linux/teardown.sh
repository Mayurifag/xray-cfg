#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source linux/common.sh

assert_root "$@"

systemctl disable --now proxies-cfg-geodata.timer 2>/dev/null || true
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
systemctl disable "$SERVICE_NAME" 2>/dev/null || true
rm -f "/etc/systemd/system/$SERVICE_NAME.service" \
           /etc/systemd/system/proxies-cfg-geodata.service \
           /etc/systemd/system/proxies-cfg-geodata.timer

# Legacy cleanup (xray-cfg-* + ancient xray-* services). No-op on fresh installs.
for svc in xray-cfg-singbox xray-cfg-geodata.timer xray-cfg-geodata xray xray-geodata.timer xray-geodata; do
    systemctl disable --now "$svc" 2>/dev/null || true
    systemctl stop "$svc" 2>/dev/null || true
done
rm -f /etc/systemd/system/xray-cfg-singbox.service \
           /etc/systemd/system/xray-cfg-geodata.service \
           /etc/systemd/system/xray-cfg-geodata.timer \
           /etc/systemd/system/xray-geodata.service \
           /etc/systemd/system/xray-geodata.timer
rm -rf /etc/systemd/system/xray.service.d 2>/dev/null || true
ip link delete xray0 2>/dev/null || true
ip rule del not fwmark 255 lookup 100 pref 9000 2>/dev/null || true
ip route flush table 100 2>/dev/null || true

systemctl daemon-reload

deadline=$(($(date +%s) + 5))
while (( $(date +%s) < deadline )); do
    pgrep -x sing-box >/dev/null || break
    sleep 1
done
pgrep -x sing-box >/dev/null && pkill -KILL -x sing-box 2>/dev/null || true
echo '[teardown] complete'
