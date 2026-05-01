#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source macos/common.sh
export RESTART_HOOK=restart_proxy
exec bash shared/remove_domain.sh "$@"
