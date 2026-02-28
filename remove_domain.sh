#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_jq

if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo "Error: config.json is not valid JSON. Aborting."
    exit 1
fi

git_pull_if_clean

DOMAIN=${1:-}

if [[ -z "$DOMAIN" ]]; then
    read -p "Enter entry to remove (e.g., example.com, geoip:google, geosite:youtube): " DOMAIN
fi
DOMAIN=$(format_domain "$DOMAIN")

PROP='domain'
[[ "$DOMAIN" == geoip:* ]] && PROP='ip'

# Check if the entry exists in the config
FOUND=$(jq --arg dom "$DOMAIN" --arg prop "$PROP" \
  '[.routing.rules[] | select(.[$prop] != null and (.[$prop] | index($dom)))] | length' \
  "$CONFIG_FILE")

if [[ "$FOUND" == "0" ]]; then
    echo "$DOMAIN not found in any routing rules. Exiting."
    exit 0
fi

# Remove the entry from any rule that has it
jq --arg dom "$DOMAIN" --arg prop "$PROP" '
  .routing.rules = [
    .routing.rules[] |
    if .[$prop] != null then
      .[$prop] = [.[$prop][] | select(. != $dom)]
    else
      .
    end
  ]
' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"

if ! jq empty "$CONFIG_FILE.tmp" 2>/dev/null; then
    rm -f "$CONFIG_FILE.tmp"
    echo "Error: jq produced invalid JSON. config.json unchanged."
    exit 1
fi
mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
echo "Success: Removed $DOMAIN from routing rules."
git_commit_and_push "chore(routing): remove $DOMAIN from routing rules"

restart_xray