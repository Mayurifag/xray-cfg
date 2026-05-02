#!/bin/bash
# Cross-platform add-domain core. Caller must cd to repo root, source platform
# common.sh (defines restart_proxy), and export RESTART_HOOK=restart_proxy.
set -euo pipefail

: "${RESTART_HOOK:?RESTART_HOOK must be set by caller}"

git_pull_if_clean

DOMAIN=${1:-}
PROXY_INPUT=${2:-}

[[ -n "$DOMAIN" ]] || read -rp 'Enter domain (e.g. example.com): ' DOMAIN
DOMAIN=$(format_domain "$DOMAIN")

TAGS=()
while IFS= read -r line; do TAGS+=("$line"); done < <(python3 shared/proxies_conf.py tags "$PROXIES_CONF")
(( ${#TAGS[@]} > 0 )) || { echo "Error: no proxy tags with [domains] in $PROXIES_CONF." >&2; exit 1; }

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

python3 shared/proxies_conf.py add-domain "$PROXY" "$DOMAIN" "$PROXIES_CONF"
git_commit_and_push "chore(routing): add $DOMAIN to $PROXY"

"$RESTART_HOOK"
