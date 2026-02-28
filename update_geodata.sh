#!/bin/bash
set -euo pipefail

ASSET_DIR=/usr/share/v2ray
GEOIP_URL=https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
GEOSITE_URL=https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat

sudo mkdir -p "$ASSET_DIR"

echo "Downloading geoip.dat..." >&2
sudo curl -fsSL --retry 3 --retry-delay 2 -o "$ASSET_DIR/geoip.dat" "$GEOIP_URL"

echo "Downloading geosite.dat (from dlc.dat)..." >&2
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
