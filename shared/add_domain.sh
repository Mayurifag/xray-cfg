#!/bin/bash
# Cross-platform add-domain core. Caller must cd to repo root, source platform
# common.sh (defines restart_proxy), and export RESTART_HOOK=restart_proxy.
set -euo pipefail

: "${RESTART_HOOK:?RESTART_HOOK must be set by caller}"

ensure_jq

if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo "Error: $CONFIG_FILE is not valid JSON. Aborting." >&2
    exit 1
fi

git_pull_if_clean

DOMAIN=${1:-}
PROXY_INPUT=${2:-}

[[ -n "$DOMAIN" ]] || read -rp 'Enter domain (e.g. example.com): ' DOMAIN
DOMAIN=$(format_domain "$DOMAIN")

TAGS=()
while IFS= read -r line; do TAGS+=("$line"); done < <(get_proxy_tags)
(( ${#TAGS[@]} > 0 )) || { echo "Error: no outbound rules with .domain in $CONFIG_FILE." >&2; exit 1; }

if [[ -z "$PROXY_INPUT" ]]; then
    echo 'Available proxy tags:'
    for i in "${!TAGS[@]}"; do echo "$((i+1))) ${TAGS[$i]}"; done
    while true; do
        read -rp "Select proxy by number (1-${#TAGS[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#TAGS[@]} )); then
            PROXY="${TAGS[$((choice-1))]}"; break
        fi
        echo 'Invalid selection.'
    done
elif [[ "$PROXY_INPUT" =~ ^[0-9]+$ ]] && (( PROXY_INPUT >= 1 && PROXY_INPUT <= ${#TAGS[@]} )); then
    PROXY="${TAGS[$((PROXY_INPUT-1))]}"
elif printf ' %s ' "${TAGS[@]}" | grep -q " ${PROXY_INPUT} "; then
    PROXY="$PROXY_INPUT"
else
    echo "Error: invalid proxy: $PROXY_INPUT" >&2; exit 1
fi

ALREADY=$(jq --arg tag "$PROXY" --arg dom "$DOMAIN" \
  '[.route.rules[] | select(.outbound == $tag) | (.domain // []) | contains([$dom])] | any' \
  "$CONFIG_FILE")
if [[ "$ALREADY" == "true" ]]; then
    echo "No-op: $DOMAIN already in $PROXY."
    exit 0
fi

jq --arg tag "$PROXY" --arg dom "$DOMAIN" '
  .route.rules = [
    .route.rules[] |
    if .outbound == $tag and (.domain != null) then
      .domain = ((.domain + [$dom]) | unique)
    else . end
  ]
' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"

jq empty "$CONFIG_FILE.tmp" >/dev/null || { rm -f "$CONFIG_FILE.tmp"; echo 'jq produced invalid JSON' >&2; exit 1; }
mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
echo "Added $DOMAIN to $PROXY."
git_commit_and_push "chore(routing): add $DOMAIN to $PROXY"

"$RESTART_HOOK"
