#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source linux/common.sh
ensure_jq

SETUP=linux/setup.sh
TEARDOWN=linux/teardown.sh
export CONFIG_FILE SETUP TEARDOWN
exec bash shared/test_core.sh
