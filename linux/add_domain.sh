#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source linux/common.sh
export RESTART_HOOK=restart_proxy
exec bash shared/add_domain.sh "$@"
