#!/bin/bash
# Sourced by every bash script. Caller must `cd` to the repo root first.

CONFIG_FILE=config_base.json
SECRETS_FILE=secrets.ejson

ensure_jq() {
    command -v jq >/dev/null 2>&1 || { echo 'Error: jq required but not in PATH.' >&2; exit 1; }
}

format_domain() {
    local d="$1"
    d="${d#domain:}"
    d="${d#http://}"
    d="${d#https://}"
    echo "${d%%/*}"
}

get_proxy_tags() {
    jq -r '.route.rules[] | select(.domain != null) | .outbound' "$CONFIG_FILE" | sort -u
}

ejson_decrypt_secret() {
    local key="$1"
    command -v ejson >/dev/null || { echo 'Error: ejson required.' >&2; exit 1; }
    ejson decrypt "$SECRETS_FILE" | python3 -c '
import sys, json
sys.stdout.write(json.load(sys.stdin)[sys.argv[1]])
' "$key"
}

generate_singbox_config() {
    local secrets
    secrets=$(ejson decrypt "$SECRETS_FILE")
    mkdir -p "$RUNTIME_DIR"
    # sing-box resolves relative paths against its WorkingDirectory; pass absolute.
    python3 shared/build_config.py "$CONFIG_FILE" "$secrets" "$(pwd)/$RULE_SET_DIR" \
        > "$SINGBOX_CONFIG"
}

git_pull_if_clean() {
    local branch default unpushed
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
    default=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||') || return 0
    if [[ "$branch" == "$default" ]]; then
        unpushed=$(git log "origin/$branch..HEAD" --oneline 2>/dev/null) || true
        [[ -z "$unpushed" ]] && git pull --ff-only
    fi
}

git_commit_and_push() {
    git add "$CONFIG_FILE"
    if ! git diff --cached --quiet; then
        git commit -m "$1"
        git push
    fi
}
