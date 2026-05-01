#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

source linux/common.sh
source shared/constants.sh

mkdir -p "$RUNTIME_DIR/bin" "$RULE_SET_DIR" "$GEODATA_DIR"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  SINGBOX_ARCH=linux-amd64 ;;
    aarch64) SINGBOX_ARCH=linux-arm64 ;;
    *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

SINGBOX_URL="https://github.com/$SINGBOX_REPO/releases/download/v$SINGBOX_VERSION/sing-box-$SINGBOX_VERSION-$SINGBOX_ARCH.tar.gz"
SINGBOX_TAR="$RUNTIME_DIR/sing-box-$SINGBOX_VERSION-$SINGBOX_ARCH.tar.gz"

echo "[setup] arch=$ARCH sing-box-extended=$SINGBOX_VERSION"

if [[ ! -x "$SINGBOX_BIN" ]]; then
    if [[ ! -s "$SINGBOX_TAR" ]]; then
        echo "[setup] downloading sing-box-extended..."
        curl -fsSL --retry 3 --retry-delay 2 -o "$SINGBOX_TAR.tmp" "$SINGBOX_URL"
        mv "$SINGBOX_TAR.tmp" "$SINGBOX_TAR"
    fi
    tar -xzf "$SINGBOX_TAR" -C "$RUNTIME_DIR/bin" --strip-components=1
fi
chmod +x "$SINGBOX_BIN"

echo '[setup] geodata + rule-sets'
bash linux/update_geodata.sh

echo '[setup] build config'
generate_singbox_config

echo '[setup] validate config'
"$SINGBOX_BIN" check -c "$SINGBOX_CONFIG"

echo "[setup] install systemd unit ($SERVICE_NAME)"
SINGBOX_BIN_ABS="$(pwd)/$SINGBOX_BIN"
SINGBOX_CONFIG_ABS="$(pwd)/$SINGBOX_CONFIG"
sudo tee "/etc/systemd/system/$SERVICE_NAME.service" >/dev/null <<EOF
[Unit]
Description=proxies-cfg sing-box-extended TUN proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$SINGBOX_BIN_ABS run -c $SINGBOX_CONFIG_ABS
Restart=on-failure
RestartSec=5
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/proxies-cfg-geodata.service >/dev/null <<EOF
[Unit]
Description=proxies-cfg daily geodata refresh
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$(pwd)
ExecStart=/bin/bash linux/update_geodata.sh
EOF

sudo tee /etc/systemd/system/proxies-cfg-geodata.timer >/dev/null <<'EOF'
[Unit]
Description=proxies-cfg daily geodata refresh

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"
sudo systemctl enable --now proxies-cfg-geodata.timer

echo '[setup] wait for TUN'
deadline=$(($(date +%s) + 15))
tun_iface=""
while (( $(date +%s) < deadline )); do
    tun_iface=$(ip -o addr show | awk -v ip="$TUN_INET" '$3 == "inet" && $4 ~ ip { print $2; exit }')
    [[ -n "$tun_iface" ]] && break
    sleep 1
done
[[ -n "$tun_iface" ]] || { sudo systemctl status "$SERVICE_NAME" --no-pager >&2; sudo journalctl -u "$SERVICE_NAME" --no-pager -n 50 >&2; echo "FAIL: TUN $TUN_INET not up in 15s" >&2; exit 1; }
echo "[setup] TUN: $tun_iface"

sudo resolvectl flush-caches 2>/dev/null || true

for url in "${ALL_TEST_URLS[@]}"; do
    curl -sS --max-time 10 -o /dev/null "$url" && echo "  prefetch ok: $url" || echo "  prefetch warn: $url"
done

echo "[setup] complete. service=$SERVICE_NAME tun=$tun_iface"
