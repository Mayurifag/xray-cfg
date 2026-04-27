#!/bin/bash
# Cross-platform remove-domain core. Caller must source platform common.sh first
# (which defines `restart_proxy`) and export REPO_ROOT.
set -euo pipefail

: "${REPO_ROOT:?REPO_ROOT must be set by caller}"
: "${RESTART_HOOK:?RESTART_HOOK must be set by caller}"

source "$REPO_ROOT/shared/common.sh"

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

FOUND=$(jq --arg dom "$DOMAIN" --arg prop "$PROP" \
  '[.routing.rules[] | select(.[$prop] != null and (.[$prop] | index($dom)))] | length' \
  "$CONFIG_FILE")

if [[ "$FOUND" == "0" ]]; then
    echo "$DOMAIN not found in any routing rules. Exiting."
    exit 0
fi

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

"$RESTART_HOOK"
