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

restart_proxy() {
    generate_singbox_config
    sudo systemctl restart "$SERVICE_NAME"
}
