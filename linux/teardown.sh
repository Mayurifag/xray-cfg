#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source linux/common.sh

sudo systemctl disable --now proxies-cfg-geodata.timer 2>/dev/null || true
sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
sudo rm -f "/etc/systemd/system/$SERVICE_NAME.service" \
           /etc/systemd/system/proxies-cfg-geodata.service \
           /etc/systemd/system/proxies-cfg-geodata.timer

# Legacy cleanup (xray-cfg-* + ancient xray-* services). No-op on fresh installs.
for svc in xray-cfg-singbox xray-cfg-geodata.timer xray-cfg-geodata xray xray-geodata.timer xray-geodata; do
    sudo systemctl disable --now "$svc" 2>/dev/null || true
    sudo systemctl stop "$svc" 2>/dev/null || true
done
sudo rm -f /etc/systemd/system/xray-cfg-singbox.service \
           /etc/systemd/system/xray-cfg-geodata.service \
           /etc/systemd/system/xray-cfg-geodata.timer \
           /etc/systemd/system/xray-geodata.service \
           /etc/systemd/system/xray-geodata.timer
sudo rm -rf /etc/systemd/system/xray.service.d 2>/dev/null || true
sudo ip link delete xray0 2>/dev/null || true
sudo ip rule del not fwmark 255 lookup 100 pref 9000 2>/dev/null || true
sudo ip route flush table 100 2>/dev/null || true

sudo systemctl daemon-reload

deadline=$(($(date +%s) + 5))
while (( $(date +%s) < deadline )); do
    pgrep -x sing-box >/dev/null || break
    sleep 1
done
pgrep -x sing-box >/dev/null && sudo pkill -KILL -x sing-box 2>/dev/null || true
echo '[teardown] complete'
