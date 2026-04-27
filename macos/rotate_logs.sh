#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

MAX_BYTES=$((100 * 1024 * 1024))

shopt -s nullglob
for f in "$RUNTIME_DIR"/*.log "$XRAY_DIR"/*.log; do
    [[ -f "$f" ]] || continue
    size=$(stat -f %z "$f")
    if (( size > MAX_BYTES )); then
        echo "Truncating $f ($size bytes)" >&2
        : > "$f"
    fi
done
