#!/bin/bash
# macOS-specific helpers. Sourced after caller cd's to repo root.

source shared/common.sh

RUNTIME_DIR=macos/runtime
SINGBOX_DIR="$RUNTIME_DIR/bin"
SINGBOX_BIN="$SINGBOX_DIR/sing-box"
SINGBOX_CONFIG="$RUNTIME_DIR/config.json"
RULE_SET_DIR="$RUNTIME_DIR/rule-sets"
GEODATA_DIR="$RUNTIME_DIR/geodata"
SINGBOX_LOG="$RUNTIME_DIR/singbox.log"

LAUNCH_DAEMON_DIR=/Library/LaunchDaemons
LABELS=(com.proxies-cfg.singbox com.proxies-cfg.geodata)
# Cleaned up by teardown if present.
LEGACY_LABELS=(com.xray-cfg.singbox com.xray-cfg.geodata com.xray-cfg.xray com.xray-cfg.logrotate)

# IPv4 inside the TUN's /30. Must stay in sync with config_base.json.
TUN_INET=172.19.0.1

assert_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "[macos] re-exec under sudo (using macos_sudo_password from secrets.ejson)" >&2
        local pw script
        pw=$(ejson_decrypt_secret macos_sudo_password)
        script="$(pwd)/$0"
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

ensure_curl_http3() {
    local candidates=(/opt/homebrew/opt/curl/bin/curl /usr/local/opt/curl/bin/curl curl)
    for c in "${candidates[@]}"; do
        if command -v "$c" >/dev/null 2>&1 && "$c" --http3 -V >/dev/null 2>&1; then
            echo "$c"; return 0
        fi
    done
    if command -v brew >/dev/null 2>&1; then
        brew install curl >&2
        local brewed=/opt/homebrew/opt/curl/bin/curl
        [[ -x "$brewed" ]] || brewed=/usr/local/opt/curl/bin/curl
        [[ -x "$brewed" ]] && echo "$brewed" && return 0
    fi
    echo "Error: no curl with HTTP/3 support found." >&2
    return 1
}

restart_proxy() {
    if [[ $EUID -ne 0 ]]; then
        local pw
        pw=$(ejson_decrypt_secret macos_sudo_password)
        printf '%s\n' "$pw" | sudo -S -k -p '' bash -c "cd $(pwd) && source macos/common.sh && restart_proxy"
        return $?
    fi
    generate_singbox_config
    launchctl kickstart -k system/com.proxies-cfg.singbox
}
