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
PROXY_INPUT=${2:-}

if [[ -z "$DOMAIN" ]]; then
    read -p "Enter domain (e.g., example.com): " DOMAIN
fi
DOMAIN=$(format_domain "$DOMAIN")

# Get list of existing proxy tags
mapfile -t TAGS < <(get_proxy_tags)

if [[ ${#TAGS[@]} -eq 0 ]]; then
    echo "Error: No outbound rules with domains found in config.json."
    exit 1
fi

# Interactive proxy selection if not provided inline
if [[ -z "$PROXY_INPUT" ]]; then
    echo "Available proxy tags:"
    for i in "${!TAGS[@]}"; do
        echo "$((i+1))) ${TAGS[$i]}"
    done

    while true; do
        read -p "Select proxy by number (1-${#TAGS[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#TAGS[@]} )); then
            PROXY="${TAGS[$((choice-1))]}"
            break
        else
            echo "Invalid selection. Try again."
        fi
    done
else
    # Allow passing either the integer OR the exact tag inline
    if [[ "$PROXY_INPUT" =~ ^[0-9]+$ ]] && (( PROXY_INPUT >= 1 && PROXY_INPUT <= ${#TAGS[@]} )); then
        PROXY="${TAGS[$((PROXY_INPUT-1))]}"
    elif [[ " ${TAGS[*]} " =~ " ${PROXY_INPUT} " ]]; then
        PROXY="$PROXY_INPUT"
    else
        echo "Error: Invalid proxy tag or number: $PROXY_INPUT"
        exit 1
    fi
fi

ALREADY_PRESENT=$(jq --arg tag "$PROXY" --arg dom "$DOMAIN" \
  '[.routing.rules[] | select(.outboundTag == $tag) | (.domain // []) | contains([$dom])] | any' \
  "$CONFIG_FILE")

if [[ "$ALREADY_PRESENT" == "true" ]]; then
    echo "No-op: $DOMAIN is already in $PROXY. No changes made."
    exit 0
fi

# Inject safely avoiding duplicates
jq --arg tag "$PROXY" --arg dom "$DOMAIN" '
  .routing.rules = [
    .routing.rules[] |
    if .outboundTag == $tag then
      .domain = ((.domain + [$dom]) | unique)
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
echo "Success: Added $DOMAIN to $PROXY outbound rule."
git_commit_and_push "chore(routing): add $DOMAIN to $PROXY"

restart_xray
