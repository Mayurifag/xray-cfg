#!/bin/bash
# Platform-agnostic helpers for xray-cfg.
# Sourced by linux/common.sh and macos/common.sh; never run directly.
# Callers own SCRIPT_DIR, CONFIG_FILE, set -euo pipefail.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${CONFIG_FILE:-$REPO_ROOT/config.json}"
SECRETS_FILE="${SECRETS_FILE:-$REPO_ROOT/secrets.ejson}"

format_domain() {
    local dom="$1"
    local prefix="domain:"

    if [[ "$dom" == geosite:* ]] || [[ "$dom" == geoip:* ]]; then
        echo "$dom"
        return
    elif [[ "$dom" == domain:* ]]; then
        dom="${dom#domain:}"
    fi

    dom="${dom#http://}"
    dom="${dom#https://}"
    dom="${dom%%/*}"

    echo "${prefix}${dom}"
}

get_proxy_tags() {
    jq -r '.routing.rules[] | select(.domain != null) | .outboundTag' "$CONFIG_FILE" | sort -u
}

ejson_decrypt_secret() {
    local key="$1"
    if ! command -v ejson &>/dev/null; then
        echo "Error: ejson not installed. See README.md." >&2
        exit 1
    fi
    ejson decrypt "$SECRETS_FILE" | python3 -c '
import sys, json
d = json.load(sys.stdin)
sys.stdout.write(d[sys.argv[1]])
' "$key"
}

git_pull_if_clean() {
    local branch default unpushed
    branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
    default=$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||') || return 0
    if [[ "$branch" == "$default" ]]; then
        unpushed=$(git -C "$REPO_ROOT" log "origin/$branch..HEAD" --oneline 2>/dev/null) || true
        if [[ -z "$unpushed" ]]; then
            echo 'Pulling latest changes...'
            git -C "$REPO_ROOT" pull --ff-only
        fi
    fi
}

git_commit_and_push() {
    local msg="$1"
    git -C "$REPO_ROOT" add config.json
    if ! git -C "$REPO_ROOT" diff --cached --quiet; then
        git -C "$REPO_ROOT" commit -m "$msg"
        git -C "$REPO_ROOT" push
        echo 'Changes committed and pushed.'
    fi
}
