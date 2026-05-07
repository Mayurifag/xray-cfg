#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source shared/ci_core.sh
ci_core macos macos/*.sh shared/*.sh linux/*.sh
for p in macos/plists/*.plist; do plutil -lint "$p" >/dev/null; done
echo 'macOS ci: shell + plist + python + ruff + git-crypt pass'
