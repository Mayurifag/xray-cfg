#!/bin/bash
# macOS-specific helpers. Sources shared/common.sh first.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

source "$REPO_ROOT/shared/common.sh"

RUNTIME_DIR="$SCRIPT_DIR/runtime"
XRAY_DIR="$RUNTIME_DIR/bin/xray"
SINGBOX_DIR="$RUNTIME_DIR/bin/sing_box"
XRAY_BIN="$XRAY_DIR/xray"
SINGBOX_BIN="$SINGBOX_DIR/sing-box"
XRAY_CONFIG="$XRAY_DIR/config.json"
SINGBOX_CONFIG="$RUNTIME_DIR/singbox-tun.json"
XRAY_ERROR_LOG="$RUNTIME_DIR/xray-error.log"
SINGBOX_LOG="$RUNTIME_DIR/singbox.log"
PID_FILE="$RUNTIME_DIR/proxy.pid"

LAUNCH_DAEMON_DIR=/Library/LaunchDaemons
LABELS=(
    com.xray-cfg.xray
    com.xray-cfg.singbox
    com.xray-cfg.geodata
    com.xray-cfg.logrotate
)

write_phase() {
    echo "[$(date '+%H:%M:%S')] [$1] $2" >&2
}

assert_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "[macos] re-exec under sudo (using macos_sudo_password from secrets.ejson)" >&2
        local pw
        pw=$(ejson_decrypt_secret macos_sudo_password)
        local script
        script="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
        printf '%s\n' "$pw" | sudo -S -k -p '' bash "$script" "$@"
        exit $?
    fi
}

ensure_jq() {
    if ! command -v jq &>/dev/null; then
        if command -v brew &>/dev/null; then
            echo "[macos] installing jq via brew..." >&2
            brew install jq
        else
            echo "Error: jq not installed and brew not available." >&2
            exit 1
        fi
    fi
}

# Locate a curl binary that supports HTTP/3 (system curl 8.x on macOS is
# linked against SecureTransport/LibreSSL and lacks --http3). Brew's curl
# is built with nghttp3+ngtcp2 and supports it. Installs brew curl on
# demand. Echoes the path of the http3-capable curl on success.
ensure_curl_http3() {
    local candidates=(
        /opt/homebrew/opt/curl/bin/curl
        /usr/local/opt/curl/bin/curl
        curl
    )
    for c in "${candidates[@]}"; do
        if command -v "$c" >/dev/null 2>&1 && "$c" --http3 -V >/dev/null 2>&1; then
            echo "$c"
            return 0
        fi
    done
    if command -v brew >/dev/null 2>&1; then
        echo "[macos] installing brew curl (HTTP/3) ..." >&2
        brew install curl >&2
        local brewed=/opt/homebrew/opt/curl/bin/curl
        [[ -x "$brewed" ]] || brewed=/usr/local/opt/curl/bin/curl
        if [[ -x "$brewed" ]] && "$brewed" --http3 -V >/dev/null 2>&1; then
            echo "$brewed"
            return 0
        fi
    fi
    echo "Error: no curl with HTTP/3 support found and brew unavailable." >&2
    return 1
}

generate_xray_config() {
    local secrets
    secrets=$(ejson decrypt "$SECRETS_FILE")
    mkdir -p "$XRAY_DIR"
    XRAY_ERROR_LOG_PATH="$XRAY_ERROR_LOG" \
        python3 "$REPO_ROOT/shared/config_transform.py" macos "$CONFIG_FILE" "$secrets" \
        > "$XRAY_CONFIG"
}

restart_proxy() {
    generate_xray_config
    echo "[macos] kickstart xray daemon..." >&2
    launchctl kickstart -k system/com.xray-cfg.xray
}
