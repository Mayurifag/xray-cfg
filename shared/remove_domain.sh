#!/bin/bash
# Cross-platform remove-domain core. Caller must cd to repo root, source
# platform common.sh, and export RESTART_HOOK=restart_proxy.
set -euo pipefail

: "${RESTART_HOOK:?RESTART_HOOK must be set by caller}"

git_pull_if_clean

DOMAIN=${1:-}
[[ -n "$DOMAIN" ]] || read -rp 'Enter domain to remove: ' DOMAIN
DOMAIN=$(format_domain "$DOMAIN")

python3 shared/proxies_conf.py remove-domain "$DOMAIN" "$PROXIES_CONF"
git_commit_and_push "chore(routing): remove $DOMAIN"

"$RESTART_HOOK"
