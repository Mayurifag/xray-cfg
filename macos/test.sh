#!/bin/bash
# Integration test: teardown -> verify direct -> setup -> verify proxied -> QUIC -> DNS sanity.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

check_ip() { curl -s --max-time 10 "$1" 2>/dev/null | tr -d '[:space:]' || true; }

assert_nonempty() {
    if [[ -z "$2" ]]; then
        echo "FAIL: $1 returned empty IP" >&2; exit 1
    fi
    echo "  $1: $2"
}

assert_ne() {
    if [[ "$2" == "$4" ]]; then
        echo "FAIL: $1 ($2) == $3 ($4) — outbounds not routing distinctly" >&2; exit 1
    fi
}

bash "$SCRIPT_DIR/teardown.sh"

echo "=== Verify: proxy down ==="
DIRECT=$(check_ip https://checkip.amazonaws.com)
IT=$(check_ip https://eth0.me)
RU=$(check_ip https://ident.me)
echo "  direct (checkip.amazonaws.com): ${DIRECT:-<unresolved>}"
echo "  it     (eth0.me):               ${IT:-<unresolved>}"
echo "  ru     (ident.me):              ${RU:-<unresolved>}"

# checkip.amazonaws.com must always resolve — represents the user's real IP.
assert_nonempty 'direct (checkip.amazonaws.com)' "$DIRECT"

# eth0.me / ident.me may be blocked by a local resolver (e.g. dnscrypt-proxy)
# when the proxy is down — empty is acceptable here. Only fail if a non-empty
# value disagrees with the real IP, which would indicate the proxy is still
# active.
for pair in "it=$IT" "ru=$RU"; do
    label="${pair%%=*}"
    ip="${pair#*=}"
    if [[ -n "$ip" && "$ip" != "$DIRECT" ]]; then
        echo "FAIL: $label IP ($ip) != direct ($DIRECT) — proxy still routing" >&2
        exit 1
    fi
done
echo "  All resolvable checkers agree on real IP: $DIRECT"

jq empty "$CONFIG_FILE" >/dev/null || { echo "config.json invalid" >&2; exit 1; }

echo "=== Setup ==="
bash "$SCRIPT_DIR/setup.sh"

echo "=== Verify: outbounds distinct ==="
DIRECT=$(check_ip https://checkip.amazonaws.com)
IT=$(check_ip https://eth0.me)
RU=$(check_ip https://ident.me)
assert_nonempty 'direct (checkip.amazonaws.com)' "$DIRECT"
assert_nonempty 'proxy_it (eth0.me)'             "$IT"
assert_nonempty 'proxy_ru (ident.me)'            "$RU"

assert_ne 'direct' "$DIRECT" 'proxy_it' "$IT"
assert_ne 'direct' "$DIRECT" 'proxy_ru' "$RU"
assert_ne 'proxy_it' "$IT" 'proxy_ru' "$RU"

echo "  direct   : $DIRECT"
echo "  proxy_it : $IT"
echo "  proxy_ru : $RU"
echo "  All three outbounds distinct."

echo "=== Verify: QUIC routing ==="
CURL_H3=$(ensure_curl_http3)
echo "  using $CURL_H3 for HTTP/3"

QUIC_IT=$("$CURL_H3" -s --http3 --max-time 10 https://eth0.me  | tr -d '[:space:]' || true)
QUIC_RU=$("$CURL_H3" -s --http3 --max-time 10 https://ident.me | tr -d '[:space:]' || true)
assert_nonempty 'eth0.me QUIC'  "$QUIC_IT"
assert_nonempty 'ident.me QUIC' "$QUIC_RU"

[[ "$QUIC_IT" == "$IT" ]] || { echo "FAIL: QUIC proxy_it ($QUIC_IT) != TLS ($IT)" >&2; exit 1; }
[[ "$QUIC_RU" == "$RU" ]] || { echo "FAIL: QUIC proxy_ru ($QUIC_RU) != TLS ($RU)" >&2; exit 1; }
echo "  QUIC proxy_it: $QUIC_IT (matches TLS)"
echo "  QUIC proxy_ru: $QUIC_RU (matches TLS)"

echo "=== Verify: DNS sanity ==="
RESOLVED=$(dscacheutil -q host -a name checkip.amazonaws.com | awk '/^ip_address:/ {print $2; exit}')
[[ -n "$RESOLVED" ]] || { echo "FAIL: dscacheutil returned no IP for checkip.amazonaws.com" >&2; exit 1; }
echo "  DNS resolves checkip.amazonaws.com -> $RESOLVED"

echo "=== PASS ==="
