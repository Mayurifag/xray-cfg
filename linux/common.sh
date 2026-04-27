#!/bin/bash
# Linux-specific helpers. Sources shared/common.sh first.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

source "$REPO_ROOT/shared/common.sh"

ensure_jq() {
    if ! command -v jq &>/dev/null; then
        echo "jq is required. Installing..."
        yay -S --noconfirm jq
    fi
}

generate_config() {
    local secrets
    secrets=$(ejson decrypt "$SECRETS_FILE")
    sudo mkdir -p /etc/xray
    python3 "$REPO_ROOT/shared/config_transform.py" linux "$CONFIG_FILE" "$secrets" \
        | sudo tee /etc/xray/config.json >/dev/null
}

restart_xray() {
    generate_config
    echo "Restarting Xray proxy to apply changes..."
    sudo systemctl restart xray
}

restart_proxy() { restart_xray; }
