#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

assert_root "$@"

dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true
echo "DNS cache flushed."
