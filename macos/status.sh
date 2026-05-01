#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source macos/common.sh
assert_root "$@"

for label in "${LABELS[@]}"; do
    echo "=== $label ==="
    launchctl print "system/$label" 2>/dev/null | grep -E '^\s+(state|pid|last exit code)' || echo '  not loaded'
    echo
done

echo "=== processes ==="
pgrep -lx sing-box || echo '  sing-box not running'

echo "=== utun ==="
ifconfig | awk -v ip="$TUN_INET" '
    /^utun[0-9]+: / { iface=$1; sub(/:/,"",iface); next }
    $1 == "inet" && $2 == ip { print iface }
'
