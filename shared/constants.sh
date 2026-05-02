#!/bin/bash
# Cross-platform constants. Sourced (not executed).

SINGBOX_VERSION="1.13.11-extended-2.0.1"
SINGBOX_REPO="shtorm-7/sing-box-extended"

GEOIP_URL="https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/release/geoip.dat"
GEOSITE_URL="https://raw.githubusercontent.com/runetfreedom/russia-blocked-geosite/release/geosite.dat"

DIRECT_TEST_URL="https://checkip.amazonaws.com"
PROXY_IT_TEST_URL="https://eth0.me"
PROXY_RU_TEST_URL="https://ident.me"
ALL_TEST_URLS=("$DIRECT_TEST_URL" "$PROXY_IT_TEST_URL" "$PROXY_RU_TEST_URL")

# IPv4 inside the TUN's /30. Must match address in shared/build_config.py base.
TUN_INET=172.19.0.1
