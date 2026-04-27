#!/bin/bash
set -euo pipefail

echo "=== Teardown ==="

sudo systemctl disable --now xray-geodata.timer 2>/dev/null || true
sudo rm -f /etc/systemd/system/xray-geodata.service /etc/systemd/system/xray-geodata.timer
sudo systemctl stop xray 2>/dev/null || true
# xray0 persists after service stop — ExecStopPost only cleans ip rules/routes
sudo ip link delete xray0 2>/dev/null || true
sudo ip rule del not fwmark 255 lookup 100 pref 9000 2>/dev/null || true
sudo ip route flush table 100 2>/dev/null || true

echo "  Teardown complete."