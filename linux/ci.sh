#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source shared/ci_core.sh
ci_core linux linux/*.sh shared/*.sh
echo 'linux ci: shell + python + ruff + git-crypt pass'
