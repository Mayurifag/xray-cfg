#!/bin/bash
# Cross-platform remove-domain core. Caller must cd to repo root, source
# platform common.sh, and export RESTART_HOOK=restart_proxy.
set -euo pipefail

: "${RESTART_HOOK:?RESTART_HOOK must be set by caller}"

ensure_jq

if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo "Error: $CONFIG_FILE is not valid JSON." >&2; exit 1
fi

git_pull_if_clean

DOMAIN=${1:-}
[[ -n "$DOMAIN" ]] || read -rp 'Enter domain to remove: ' DOMAIN
DOMAIN=$(format_domain "$DOMAIN")

FOUND=$(jq --arg dom "$DOMAIN" \
  '[.route.rules[] | select(.domain != null and (.domain | index($dom)))] | length' \
  "$CONFIG_FILE")
if [[ "$FOUND" == "0" ]]; then
    echo "$DOMAIN not found in any rule."
    exit 0
fi

jq --arg dom "$DOMAIN" '
  .route.rules = [
    .route.rules[] |
    if .domain != null then
      .domain = [.domain[] | select(. != $dom)]
    else . end
  ]
' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"

jq empty "$CONFIG_FILE.tmp" >/dev/null || { rm -f "$CONFIG_FILE.tmp"; echo 'jq produced invalid JSON' >&2; exit 1; }
mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
echo "Removed $DOMAIN."
git_commit_and_push "chore(routing): remove $DOMAIN"

"$RESTART_HOOK"
