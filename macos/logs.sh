#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

assert_root "$@"

mkdir -p "$RUNTIME_DIR"
touch "$XRAY_ERROR_LOG" "$SINGBOX_LOG" \
      "$RUNTIME_DIR/xray-stdout.log" "$RUNTIME_DIR/xray-stderr.log" \
      "$RUNTIME_DIR/singbox-stdout.log" "$RUNTIME_DIR/singbox-stderr.log"

exec tail -F \
    "$XRAY_ERROR_LOG" \
    "$SINGBOX_LOG" \
    "$RUNTIME_DIR/xray-stdout.log" \
    "$RUNTIME_DIR/xray-stderr.log" \
    "$RUNTIME_DIR/singbox-stdout.log" \
    "$RUNTIME_DIR/singbox-stderr.log"
