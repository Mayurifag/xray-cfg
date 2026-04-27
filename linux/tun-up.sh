#!/bin/bash
set -euo pipefail

until ip link show xray0 >/dev/null 2>&1; do sleep 0.1; done
ip addr add 172.19.0.1/30 dev xray0 2>/dev/null || true
ip route add default dev xray0 table 100 2>/dev/null || true
ip rule add not fwmark 255 lookup 100 pref 9000 2>/dev/null || true
tc qdisc replace dev xray0 root fq 2>/dev/null || true
resolvectl dns xray0 1.1.1.1
resolvectl default-route xray0 yes
resolvectl domain xray0 "~."
