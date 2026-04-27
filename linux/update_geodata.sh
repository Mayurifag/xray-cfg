#!/bin/bash
set -euo pipefail

ASSET_DIR=/usr/share/v2ray
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/shared/geodata_urls.sh"

sudo mkdir -p "$ASSET_DIR"

GEOIP_PATH="$ASSET_DIR/geoip.dat"
GEOSITE_PATH="$ASSET_DIR/geosite.dat"

needs_update() {
    local f="$1"
    [[ ! -s "$f" ]] && return 0
    local now mtime age_secs
    now=$(date +%s)
    mtime=$(stat -c %Y "$f")
    age_secs=$((now - mtime))
    (( age_secs > 86400 ))
}

download() {
    local url="$1" dst="$2"
    sudo curl -fsSL --retry 3 --retry-delay 2 -o "$dst.tmp" "$url"
    sudo mv "$dst.tmp" "$dst"
}

if needs_update "$GEOIP_PATH"; then
    echo "Downloading geoip.dat..." >&2
    download "$GEOIP_URL" "$GEOIP_PATH"
fi

if needs_update "$GEOSITE_PATH"; then
    echo "Downloading geosite.dat..." >&2
    download "$GEOSITE_URL" "$GEOSITE_PATH"
fi

[[ -s "$GEOIP_PATH" ]]   || { echo "Error: $GEOIP_PATH empty"   >&2; exit 1; }
[[ -s "$GEOSITE_PATH" ]] || { echo "Error: $GEOSITE_PATH empty" >&2; exit 1; }

echo "Geodata: $(stat -c '%s bytes' "$GEOIP_PATH") geoip, $(stat -c '%s bytes' "$GEOSITE_PATH") geosite"
