#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if ! command -v xray &>/dev/null; then
    yay -S --noconfirm xray-bin
fi

sudo mkdir -p /etc/systemd/system/xray.service.d

INSTALL_DIR=/usr/local/lib/xray-cfg
sudo mkdir -p "$INSTALL_DIR"
sudo cp "$SCRIPT_DIR/tun-up.sh" "$INSTALL_DIR/tun-up.sh"
sudo cp "$SCRIPT_DIR/tun-down.sh" "$INSTALL_DIR/tun-down.sh"
sudo chmod +x "$INSTALL_DIR/tun-up.sh" "$INSTALL_DIR/tun-down.sh"

cat <<EOF | sudo tee /etc/systemd/system/xray.service.d/override.conf >/dev/null
[Service]
User=root
NoNewPrivileges=false
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
Environment=XRAY_LOCATION_ASSET=/usr/share/v2ray
ExecStart=
ExecStart=/usr/bin/xray run -config /etc/xray/config.json
ExecStartPost=/usr/local/lib/xray-cfg/tun-up.sh
ExecStopPost=-/usr/local/lib/xray-cfg/tun-down.sh
EOF

sudo systemctl daemon-reload
if ! sudo systemctl is-enabled xray &>/dev/null; then
    sudo systemctl enable xray
fi

bash "$SCRIPT_DIR/update_geodata.sh"

cat <<EOF | sudo tee /etc/systemd/system/xray-geodata.service >/dev/null
[Unit]
Description=Update xray geodata
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT_DIR/update_geodata.sh
EOF

cat <<'EOF' | sudo tee /etc/systemd/system/xray-geodata.timer >/dev/null
[Unit]
Description=Daily xray geodata update

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now xray-geodata.timer

generate_config
sudo systemctl restart xray
sleep 2
sudo systemctl status xray --no-pager
