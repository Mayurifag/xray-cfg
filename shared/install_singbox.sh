#!/bin/bash
# Download + extract sing-box-extended binary if not present.
# Caller must `cd` to repo root, source platform common.sh, and export:
#   SINGBOX_ARCH (e.g. linux-amd64, darwin-arm64)
# After return: $SINGBOX_BIN exists and is executable.
set -euo pipefail
source shared/constants.sh

: "${SINGBOX_ARCH:?}" "${SINGBOX_BIN:?}" "${RUNTIME_DIR:?}"

extract_dir=$(dirname "$SINGBOX_BIN")
mkdir -p "$extract_dir" "$RUNTIME_DIR"

url="https://github.com/$SINGBOX_REPO/releases/download/v$SINGBOX_VERSION/sing-box-$SINGBOX_VERSION-$SINGBOX_ARCH.tar.gz"
tar_path="$RUNTIME_DIR/sing-box-$SINGBOX_VERSION-$SINGBOX_ARCH.tar.gz"

if [[ ! -x "$SINGBOX_BIN" ]]; then
    if [[ ! -s "$tar_path" ]]; then
        echo "[install_singbox] downloading $url" >&2
        curl -fsSL --retry 3 --retry-delay 2 -o "$tar_path.tmp" "$url"
        mv "$tar_path.tmp" "$tar_path"
    fi
    /usr/bin/env tar -xzf "$tar_path" -C "$extract_dir" --strip-components=1
fi

# macOS quarantines downloaded executables; clear so launchd can exec.
[[ "$(uname)" == Darwin ]] && xattr -d com.apple.quarantine "$SINGBOX_BIN" 2>/dev/null || true
chmod +x "$SINGBOX_BIN"
