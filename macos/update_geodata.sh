#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$REPO_ROOT/shared/geodata_urls.sh"

mkdir -p "$XRAY_DIR"

GEOIP_PATH="$XRAY_DIR/geoip.dat"
GEOSITE_PATH="$XRAY_DIR/geosite.dat"

needs_update() {
    local f="$1"
    [[ ! -s "$f" ]] && return 0
    local now mtime age_secs
    now=$(date +%s)
    mtime=$(stat -f %m "$f")
    age_secs=$((now - mtime))
    (( age_secs > 86400 ))
}

if needs_update "$GEOIP_PATH"; then
    echo "Downloading geoip.dat..." >&2
    curl -fsSL --retry 3 --retry-delay 2 -o "$GEOIP_PATH.tmp" "$GEOIP_URL"
    mv "$GEOIP_PATH.tmp" "$GEOIP_PATH"
fi

if needs_update "$GEOSITE_PATH"; then
    echo "Downloading geosite.dat..." >&2
    curl -fsSL --retry 3 --retry-delay 2 -o "$GEOSITE_PATH.tmp" "$GEOSITE_URL"
    mv "$GEOSITE_PATH.tmp" "$GEOSITE_PATH"
fi

[[ -s "$GEOIP_PATH" ]]   || { echo "Error: $GEOIP_PATH empty" >&2; exit 1; }
[[ -s "$GEOSITE_PATH" ]] || { echo "Error: $GEOSITE_PATH empty" >&2; exit 1; }

echo "Geodata: $(stat -f '%z bytes' "$GEOIP_PATH") geoip, $(stat -f '%z bytes' "$GEOSITE_PATH") geosite"
