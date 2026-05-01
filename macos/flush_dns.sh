#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source macos/common.sh
assert_root "$@"
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true
echo "DNS cache flushed."
