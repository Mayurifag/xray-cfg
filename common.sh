#!/bin/bash
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.json}"

ensure_jq() {
    if ! command -v jq &>/dev/null; then
        echo "jq is required. Installing..."
        yay -S --noconfirm jq
    fi
}

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
    # Extracts all outboundTags from routing rules that have domain arrays
    jq -r '.routing.rules[] | select(.domain != null) | .outboundTag' "$CONFIG_FILE" | sort -u
}

generate_config() {
    if ! command -v ejson &>/dev/null; then
        echo "Error: ejson not installed. See README.md." >&2
        exit 1
    fi
    local secrets
    secrets=$(ejson decrypt "$SCRIPT_DIR/secrets.ejson")
    sudo mkdir -p /etc/xray
    python3 -c "
import sys, json
tmpl = open(sys.argv[1]).read()
s = json.loads(sys.argv[2])
for k, v in [
    ('PLACEHOLDER_PROXY_RU_HOST',       s['proxy_ru']['host']),
    ('PLACEHOLDER_PROXY_RU_UUID',       s['proxy_ru']['uuid']),
    ('PLACEHOLDER_PROXY_RU_SHORT_ID',   s['proxy_ru']['short_id']),
    ('PLACEHOLDER_PROXY_RU_PUBLIC_KEY', s['proxy_ru']['public_key']),
    ('PLACEHOLDER_PROXY_IT_HOST',       s['proxy_it']['host']),
    ('PLACEHOLDER_PROXY_IT_UUID',       s['proxy_it']['uuid']),
    ('PLACEHOLDER_PROXY_IT_SHORT_ID',   s['proxy_it']['short_id']),
    ('PLACEHOLDER_PROXY_IT_PUBLIC_KEY', s['proxy_it']['public_key']),
]:
    tmpl = tmpl.replace(k, v)
sys.stdout.write(tmpl)
" "$SCRIPT_DIR/config.json" "$secrets" | sudo tee /etc/xray/config.json >/dev/null
}

restart_xray() {
    generate_config
    echo "Restarting Xray proxy to apply changes..."
    sudo systemctl restart xray
}

git_pull_if_clean() {
    local branch default unpushed
    branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
    default=$(git -C "$SCRIPT_DIR" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||') || return 0
    if [[ "$branch" == "$default" ]]; then
        unpushed=$(git -C "$SCRIPT_DIR" log "origin/$branch..HEAD" --oneline 2>/dev/null) || true
        if [[ -z "$unpushed" ]]; then
            echo 'Pulling latest changes...'
            git -C "$SCRIPT_DIR" pull --ff-only
        fi
    fi
}

git_commit_and_push() {
    local msg="$1"
    git -C "$SCRIPT_DIR" add config.json
    if ! git -C "$SCRIPT_DIR" diff --cached --quiet; then
        git -C "$SCRIPT_DIR" commit -m "$msg"
        git -C "$SCRIPT_DIR" push
        echo 'Changes committed and pushed.'
    fi
}
