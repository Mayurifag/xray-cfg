#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source linux/common.sh

SETUP=linux/setup.sh
TEARDOWN=linux/teardown.sh
ADD_DOMAIN='bash linux/add_domain.sh'
REMOVE_DOMAIN='bash linux/remove_domain.sh'
export SETUP TEARDOWN ADD_DOMAIN REMOVE_DOMAIN RULE_SET_DIR SINGBOX_LOG
exec bash shared/test_core.sh
