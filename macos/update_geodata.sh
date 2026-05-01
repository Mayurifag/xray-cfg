#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source macos/common.sh
export GEODATA_DIR RULE_SET_DIR
exec bash shared/update_geodata_core.sh
