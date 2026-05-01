#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source macos/common.sh
assert_root "$@"

mkdir -p "$RUNTIME_DIR"
touch "$SINGBOX_LOG" "$RUNTIME_DIR/singbox-stdout.log" "$RUNTIME_DIR/singbox-stderr.log"
exec tail -F "$SINGBOX_LOG" "$RUNTIME_DIR/singbox-stdout.log" "$RUNTIME_DIR/singbox-stderr.log"
