#!/bin/bash
# Sourced by every bash script. Caller must `cd` to the repo root first.

PROXIES_CONF=proxies.conf
SECRETS_FILE=secrets.ejson
export PROXIES_CONF SECRETS_FILE

format_domain() {
    local d="$1"
    d="${d#domain:}"
    d="${d#http://}"
    d="${d#https://}"
    echo "${d%%/*}"
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
    mkdir -p "$RUNTIME_DIR"
    bash "$GENERATE_CONFIG" > "$SINGBOX_CONFIG"
}

git_pull_if_clean() {
    [[ -n "${NO_GIT:-}" ]] && return 0
    local branch default unpushed
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
    default=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||') || return 0
    if [[ "$branch" == "$default" ]]; then
        unpushed=$(git log "origin/$branch..HEAD" --oneline 2>/dev/null) || true
        [[ -z "$unpushed" ]] && git pull --ff-only
    fi
}

git_commit_and_push() {
    [[ -n "${NO_GIT:-}" ]] && return 0
    git add "$PROXIES_CONF"
    if ! git diff --cached --quiet; then
        git commit -m "$1"
        git push
    fi
}
