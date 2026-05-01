#!/bin/bash
# Linux-specific helpers. Sourced after caller cd's to repo root.

source shared/common.sh

RUNTIME_DIR=linux/runtime
SINGBOX_BIN="$RUNTIME_DIR/bin/sing-box"
SINGBOX_CONFIG="$RUNTIME_DIR/config.json"
RULE_SET_DIR="$RUNTIME_DIR/rule-sets"
GEODATA_DIR="$RUNTIME_DIR/geodata"

SERVICE_NAME=proxies-cfg-singbox
TUN_INET=172.19.0.1

restart_proxy() {
    generate_singbox_config
    sudo systemctl restart "$SERVICE_NAME"
}
