#!/bin/bash
set -euo pipefail

ASSET_DIR=/usr/share/v2ray
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/shared/geodata_urls.sh"

sudo mkdir -p "$ASSET_DIR"

echo "Downloading geoip.dat..." >&2
sudo curl -fsSL --retry 3 --retry-delay 2 -o "$ASSET_DIR/geoip.dat" "$GEOIP_URL"

echo "Downloading geosite.dat..." >&2
sudo curl -fsSL --retry 3 --retry-delay 2 -o "$ASSET_DIR/geosite.dat" "$GEOSITE_URL"

if [[ ! -s "$ASSET_DIR/geoip.dat" ]]; then
    echo "Error: $ASSET_DIR/geoip.dat is empty or missing" >&2
    exit 1
fi

if [[ ! -s "$ASSET_DIR/geosite.dat" ]]; then
    echo "Error: $ASSET_DIR/geosite.dat is empty or missing" >&2
    exit 1
fi

GEOIP_SIZE=$(stat -c '%s' "$ASSET_DIR/geoip.dat")
GEOSITE_SIZE=$(stat -c '%s' "$ASSET_DIR/geosite.dat")

echo "Downloaded: $ASSET_DIR/geoip.dat ($GEOIP_SIZE bytes)"
echo "Downloaded: $ASSET_DIR/geosite.dat ($GEOSITE_SIZE bytes)"
