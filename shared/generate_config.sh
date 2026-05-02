#!/bin/bash
# Print the sing-box config (built from proxies.conf + subscriptions) to stdout.
# Caller must `cd` to repo root and source platform common.sh so $RULE_SET_DIR
# (and optionally $INTERFACE_NAME) are set.
set -euo pipefail

: "${RULE_SET_DIR:?RULE_SET_DIR must be set by caller}"

command -v ejson >/dev/null || { echo 'Error: ejson required.' >&2; exit 1; }
secrets=$(ejson decrypt "$SECRETS_FILE")
[[ -n "$secrets" ]] || { echo 'Error: ejson decrypt produced empty output.' >&2; exit 1; }

args=("$PROXIES_CONF" "$secrets" "$(pwd)/$RULE_SET_DIR")
[[ -n "${INTERFACE_NAME:-}" ]] && args+=(--interface-name "$INTERFACE_NAME")

exec python3 shared/build_config.py "${args[@]}"
