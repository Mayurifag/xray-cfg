#!/bin/bash
# Linux-specific helpers. Sourced after caller cd's to repo root.

source shared/common.sh
source shared/constants.sh

RUNTIME_DIR=linux/runtime
SINGBOX_BIN="$RUNTIME_DIR/bin/sing-box"
SINGBOX_CONFIG="$RUNTIME_DIR/config.json"
SINGBOX_LOG="$RUNTIME_DIR/singbox.log"
RULE_SET_DIR="$RUNTIME_DIR/rule-sets"
GEODATA_DIR="$RUNTIME_DIR/geodata"
GENERATE_CONFIG="linux/generate_config.sh"

SERVICE_NAME=proxies-cfg-singbox

export RULE_SET_DIR GEODATA_DIR SINGBOX_LOG

assert_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "[linux] re-exec under sudo (using sudo_password from secrets.ejson)" >&2
        local pw script
        pw=$(ejson_decrypt_secret sudo_password)
        script="$(pwd)/$0"
        printf '%s\n' "$pw" | sudo -S -k -p '' bash "$script" "$@"
        exit $?
    fi
}

restart_proxy() {
    if [[ $EUID -ne 0 ]]; then
        local pw
        pw=$(ejson_decrypt_secret sudo_password)
        printf '%s\n' "$pw" | sudo -S -k -p '' bash -c "cd $(pwd) && source linux/common.sh && restart_proxy"
        return $?
    fi
    generate_singbox_config
    systemctl restart "$SERVICE_NAME"
}
