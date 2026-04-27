#!/bin/bash
# Lightweight CI for macOS: shell syntax + plist lint.
# Heavy e2e lives in `make cycle` / `make test` and requires sudo + network.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

for f in "$REPO_ROOT"/macos/*.sh "$REPO_ROOT"/shared/*.sh "$REPO_ROOT"/linux/*.sh; do
    bash -n "$f"
done

for p in "$REPO_ROOT"/macos/plists/*.plist; do
    plutil -lint "$p" >/dev/null
done

echo "macOS ci: shell + plist lint pass (run \`make cycle\` for full e2e)"
