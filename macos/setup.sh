#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

assert_root "$@"

write_phase setup 'Phase 0: paths + arch'

mkdir -p "$RUNTIME_DIR" "$XRAY_DIR" "$SINGBOX_DIR"

ARCH=$(uname -m)
case "$ARCH" in
    arm64)  XRAY_ARCH=macos-arm64-v8a; SINGBOX_ARCH=darwin-arm64 ;;
    x86_64) XRAY_ARCH=macos-64;        SINGBOX_ARCH=darwin-amd64 ;;
    *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

XRAY_VERSION="${XRAY_VERSION:-v26.3.27}"
SINGBOX_VERSION="${SINGBOX_VERSION:-1.13.11}"

XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/$XRAY_VERSION/Xray-$XRAY_ARCH.zip"
SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v$SINGBOX_VERSION/sing-box-$SINGBOX_VERSION-$SINGBOX_ARCH.tar.gz"

XRAY_ZIP="$RUNTIME_DIR/xray-$XRAY_VERSION-$XRAY_ARCH.zip"
SINGBOX_TAR="$RUNTIME_DIR/sing-box-$SINGBOX_VERSION-$SINGBOX_ARCH.tar.gz"

write_phase setup "arch=$ARCH xray=$XRAY_VERSION sing-box=$SINGBOX_VERSION"

write_phase setup 'Phase 1: download+extract'

if [[ ! -x "$XRAY_BIN" ]]; then
    if [[ ! -s "$XRAY_ZIP" ]]; then
        write_phase setup "downloading xray $XRAY_VERSION..."
        curl -fsSL --retry 3 --retry-delay 2 -o "$XRAY_ZIP.tmp" "$XRAY_URL"
        mv "$XRAY_ZIP.tmp" "$XRAY_ZIP"
    fi
    write_phase setup "extracting xray to $XRAY_DIR..."
    /usr/bin/unzip -oq "$XRAY_ZIP" -d "$XRAY_DIR"
    [[ -x "$XRAY_DIR/xray" ]] || { echo "xray binary missing after extract" >&2; exit 1; }
fi

if [[ ! -x "$SINGBOX_BIN" ]]; then
    if [[ ! -s "$SINGBOX_TAR" ]]; then
        write_phase setup "downloading sing-box $SINGBOX_VERSION..."
        curl -fsSL --retry 3 --retry-delay 2 -o "$SINGBOX_TAR.tmp" "$SINGBOX_URL"
        mv "$SINGBOX_TAR.tmp" "$SINGBOX_TAR"
    fi
    write_phase setup "extracting sing-box to $SINGBOX_DIR..."
    /usr/bin/tar -xzf "$SINGBOX_TAR" -C "$SINGBOX_DIR" --strip-components=1
    [[ -x "$SINGBOX_BIN" ]] || { echo "sing-box binary missing after extract" >&2; exit 1; }
fi

write_phase setup 'Phase 2: strip quarantine + chmod'
xattr -d com.apple.quarantine "$XRAY_BIN"     2>/dev/null || true
xattr -d com.apple.quarantine "$SINGBOX_BIN"  2>/dev/null || true
chmod +x "$XRAY_BIN" "$SINGBOX_BIN"

write_phase setup 'Phase 3: geodata'
bash "$SCRIPT_DIR/update_geodata.sh"

write_phase setup 'Phase 4: generate xray config'
generate_xray_config

write_phase setup 'Phase 5: validate xray config'
"$XRAY_BIN" run -test -c "$XRAY_CONFIG"

write_phase setup 'Phase 6: copy singbox-tun.json (from shared/)'
cp "$REPO_ROOT/shared/singbox-tun.json" "$SINGBOX_CONFIG"

write_phase setup 'Phase 7: install LaunchDaemons'

install_plist() {
    local label="$1"
    local src="$SCRIPT_DIR/plists/$label.plist"
    local dst="$LAUNCH_DAEMON_DIR/$label.plist"

    launchctl bootout "system/$label" 2>/dev/null || true
    rm -f "$dst"

    sed "s|__REPO_ROOT__|$REPO_ROOT|g" "$src" > "$dst"
    chown root:wheel "$dst"
    chmod 644 "$dst"
    plutil -lint "$dst" >/dev/null

    launchctl bootstrap system "$dst"
    write_phase setup "  installed $label"
}

for label in "${LABELS[@]}"; do
    install_plist "$label"
done

write_phase setup 'Phase 8: wait for utun'

deadline=$(($(date +%s) + 15))
utun=""
while (( $(date +%s) < deadline )); do
    utun=$(ifconfig | awk '
        /^utun[0-9]+: / { iface=$1; sub(/:/, "", iface) }
        /inet 172\.18\.0\.1/ { print iface; exit }
    ')
    [[ -n "$utun" ]] && break
    sleep 1
done

if [[ -z "$utun" ]]; then
    echo "FAIL: utun with 172.18.0.1 did not appear within 15s" >&2
    write_phase setup '--- ifconfig dump ---'
    ifconfig >&2
    write_phase setup '--- daemon status ---'
    launchctl print system/com.xray-cfg.singbox 2>&1 | head -40 >&2 || true
    exit 1
fi
write_phase setup "utun adapter: $utun"

write_phase setup 'Phase 8b: wait for routes via utun'
deadline=$(($(date +%s) + 10))
route_found=0
while (( $(date +%s) < deadline )); do
    if netstat -rn -f inet | awk -v iface="$utun" '$NF == iface { found=1; exit } END { exit !found }'; then
        route_found=1
        break
    fi
    sleep 1
done

if (( route_found == 0 )); then
    echo "FAIL: no route installed via $utun within 10s — sing-box auto_route did not take effect" >&2
    write_phase setup '--- netstat dump ---'
    netstat -rn -f inet >&2
    exit 1
fi
write_phase setup "  routes via $utun: confirmed"

write_phase setup 'Phase 9: flush DNS'
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true

write_phase setup 'Phase 10: prefetch'
for url in https://ident.me https://eth0.me https://checkip.amazonaws.com; do
    if curl -sS --max-time 10 -o /dev/null "$url"; then
        write_phase setup "  prefetch ok: $url"
    else
        write_phase setup "  prefetch warn: $url (continuing)"
    fi
done

write_phase setup 'Setup complete.'
echo "Setup complete."
echo "  utun       : $utun"
echo "  xray PID   : $(launchctl print system/com.xray-cfg.xray | awk '/pid =/ {print $3; exit}')"
echo "  singbox PID: $(launchctl print system/com.xray-cfg.singbox | awk '/pid =/ {print $3; exit}')"
