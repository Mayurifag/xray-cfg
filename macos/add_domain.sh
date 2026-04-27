#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"
export REPO_ROOT
export RESTART_HOOK=restart_proxy
source "$REPO_ROOT/shared/add_domain.sh"
