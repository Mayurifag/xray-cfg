#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

source macos/common.sh

CURL_HTTP3="$(ensure_curl_http3)"
DNS_CHECK_CMD='dscacheutil -q host -a name checkip.amazonaws.com | awk "/^ip_address:/ {print \$2; exit}"'
SETUP=macos/setup.sh
TEARDOWN=macos/teardown.sh
ADD_DOMAIN='bash macos/add_domain.sh'
REMOVE_DOMAIN='bash macos/remove_domain.sh'

export CURL_HTTP3 DNS_CHECK_CMD SETUP TEARDOWN ADD_DOMAIN REMOVE_DOMAIN RULE_SET_DIR SINGBOX_LOG
exec bash shared/test_core.sh
