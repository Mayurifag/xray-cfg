#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

source macos/common.sh
ensure_jq

CURL_HTTP3="$(ensure_curl_http3)"
DNS_CHECK_CMD='dscacheutil -q host -a name checkip.amazonaws.com | awk "/^ip_address:/ {print \$2; exit}"'
SETUP=macos/setup.sh
TEARDOWN=macos/teardown.sh

export CONFIG_FILE CURL_HTTP3 DNS_CHECK_CMD SETUP TEARDOWN
exec bash shared/test_core.sh
