#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

check_ip() {
    local url="$1"
    curl -s --max-time 10 "$url" | tr -d '[:space:]'
}

assert_nonempty() {
    local label="$1"
    local ip="$2"
    if [[ -z "$ip" ]]; then
        echo "FAIL: $label returned empty IP — check failed or endpoint unreachable"
        exit 1
    fi
    echo "  $label: $ip"
}

assert_ne() {
    local label_a="$1" ip_a="$2"
    local label_b="$3" ip_b="$4"
    if [[ "$ip_a" == "$ip_b" ]]; then
        echo "FAIL: $label_a ($ip_a) == $label_b ($ip_b) — outbounds not routing distinctly"
        exit 1
    fi
}

bash "$SCRIPT_DIR/teardown.sh"
if resolvectl dns xray0 2>/dev/null; then
    echo "FAIL: xray0 interface still has DNS configured after teardown — resolvectl revert did not run"
    exit 1
fi
echo "  DNS check: xray0 interface gone from systemd-resolved (DNS restored)"

echo "=== Verify: proxy down ==="

DIRECT_IP=$(check_ip "https://checkip.amazonaws.com")
IT_IP=$(check_ip "https://eth0.me")
RU_IP=$(check_ip "https://ident.me")

assert_nonempty "checkip.amazonaws.com" "$DIRECT_IP"
assert_nonempty "eth0.me" "$IT_IP"
assert_nonempty "ident.me" "$RU_IP"

if [[ "$DIRECT_IP" != "$IT_IP" ]] || [[ "$DIRECT_IP" != "$RU_IP" ]]; then
    echo "FAIL: After teardown, checkers returned different IPs — proxy may still be active"
    echo "  checkip.amazonaws.com: $DIRECT_IP"
    echo "  eth0.me:               $IT_IP"
    echo "  ident.me:              $RU_IP"
    exit 1
fi
echo "  All checkers agree on real IP: $DIRECT_IP"

if ! jq empty "$CONFIG_FILE" 2>&1; then
    echo "FAIL: config.json is not valid JSON — fix before running test"
    exit 1
fi

echo "=== Setup ==="

bash "$SCRIPT_DIR/setup_linux.sh"
if [[ $? -ne 0 ]]; then
    echo "FAIL: setup_linux.sh exited non-zero"
    exit 1
fi
echo "  setup_linux.sh exited 0."

echo "=== Verify: outbounds distinct ==="

DIRECT_IP=$(check_ip "https://checkip.amazonaws.com")
IT_IP=$(check_ip "https://eth0.me")
RU_IP=$(check_ip "https://ident.me")

assert_nonempty "checkip.amazonaws.com (direct)" "$DIRECT_IP"
assert_nonempty "eth0.me (proxy_it)" "$IT_IP"
assert_nonempty "ident.me (proxy_ru)" "$RU_IP"

assert_ne "direct" "$DIRECT_IP" "proxy_it" "$IT_IP"
assert_ne "direct" "$DIRECT_IP" "proxy_ru" "$RU_IP"
assert_ne "proxy_it" "$IT_IP" "proxy_ru" "$RU_IP"

echo "  direct   (checkip.amazonaws.com): $DIRECT_IP"
echo "  proxy_it (eth0.me):               $IT_IP"
echo "  proxy_ru (ident.me):              $RU_IP"
echo "  All three outbounds route to distinct IPs."

echo "=== Verify: QUIC (HTTP/3) routing ==="

if curl --http3 -V >/dev/null 2>&1; then
    QUIC_IT=$(curl -s --http3 --max-time 10 "https://eth0.me" | tr -d '[:space:]')
    QUIC_RU=$(curl -s --http3 --max-time 10 "https://ident.me" | tr -d '[:space:]')

    assert_nonempty "eth0.me QUIC (proxy_it)" "$QUIC_IT"
    assert_nonempty "ident.me QUIC (proxy_ru)" "$QUIC_RU"

    if [[ "$QUIC_IT" != "$IT_IP" ]]; then
        echo "FAIL: QUIC proxy_it ($QUIC_IT) != TLS proxy_it ($IT_IP) — QUIC bypasses routing"
        exit 1
    fi
    if [[ "$QUIC_RU" != "$RU_IP" ]]; then
        echo "FAIL: QUIC proxy_ru ($QUIC_RU) != TLS proxy_ru ($RU_IP) — QUIC bypasses routing"
        exit 1
    fi
    echo "  QUIC proxy_it (eth0.me):  $QUIC_IT (matches TLS)"
    echo "  QUIC proxy_ru (ident.me): $QUIC_RU (matches TLS)"
else
    echo "  QUIC tests skipped (curl lacks --http3 support)"
fi

if ! resolvectl dns xray0 2>/dev/null; then
    echo "FAIL: xray0 interface not found in systemd-resolved after setup — DNS not configured"
    exit 1
fi
echo "  DNS check: xray0 interface present in systemd-resolved"
RESOLVED=$(dig checkip.amazonaws.com A +short 2>/dev/null)
if [[ -z "$RESOLVED" ]]; then
    echo "FAIL: DNS resolution of checkip.amazonaws.com returned empty — DNS not working through xray"
    exit 1
fi
echo "  DNS check: checkip.amazonaws.com resolves to $RESOLVED"

echo "=== PASS ==="
