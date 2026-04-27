#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

assert_root "$@"

for label in com.xray-cfg.xray com.xray-cfg.singbox; do
    echo "=== $label ==="
    if launchctl print "system/$label" 2>/dev/null | grep -E '^\s+(state|pid|last exit code)'; then
        :
    else
        echo "  not loaded"
    fi
    echo
done

echo "=== processes ==="
pgrep -lx xray     || echo "  xray not running"
pgrep -lx sing-box || echo "  sing-box not running"

echo "=== utun ==="
ifconfig | awk '/^utun[0-9]+: / {iface=$1; sub(/:/,"",iface); next} /inet 172\.18\.0\.1/ {print iface}'
