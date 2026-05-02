#!/bin/bash
# Cross-platform integration test core. Caller must `cd` to repo root and
# export: SETUP, TEARDOWN. Optional: CURL_HTTP3, DNS_CHECK_CMD.
set -euo pipefail

source shared/constants.sh

CURL_HTTP3="${CURL_HTTP3:-curl}"
DNS_CHECK_CMD="${DNS_CHECK_CMD:-dig +short checkip.amazonaws.com A | head -1}"

check_ip()         { curl -s --max-time 10 "$1" | tr -d '[:space:]'; }
assert_nonempty()  { [[ -n "$2" ]] || { echo "FAIL: $1 empty IP" >&2; exit 1; }; echo "  $1: $2"; }
assert_ne()        { [[ "$2" != "$4" ]] || { echo "FAIL: $1 ($2) == $3 ($4)" >&2; exit 1; }; }

bash "$TEARDOWN"

echo '=== Verify: proxy down ==='
DIRECT=$(check_ip "$DIRECT_TEST_URL")
IT=$(check_ip "$PROXY_IT_TEST_URL")
RU=$(check_ip "$PROXY_RU_TEST_URL")
assert_nonempty 'direct (checkip.amazonaws.com)' "$DIRECT"
for pair in "it=$IT" "ru=$RU"; do
    label="${pair%%=*}"; ip="${pair#*=}"
    if [[ -n "$ip" && "$ip" != "$DIRECT" ]]; then
        echo "FAIL: $label IP ($ip) != direct ($DIRECT) — proxy still routing" >&2
        exit 1
    fi
done
echo "  All checkers agree on real IP: $DIRECT"

python3 shared/proxies_conf.py tags proxies.conf >/dev/null || { echo 'proxies.conf invalid' >&2; exit 1; }

echo '=== Setup ==='
bash "$SETUP"

echo '=== Verify: outbounds distinct ==='
DIRECT=$(check_ip "$DIRECT_TEST_URL")
IT=$(check_ip "$PROXY_IT_TEST_URL")
RU=$(check_ip "$PROXY_RU_TEST_URL")
assert_nonempty 'direct (checkip.amazonaws.com)' "$DIRECT"
assert_nonempty 'proxy_it (eth0.me)'             "$IT"
assert_nonempty 'proxy_ru (ident.me)'            "$RU"
assert_ne 'direct'   "$DIRECT" 'proxy_it' "$IT"
assert_ne 'direct'   "$DIRECT" 'proxy_ru' "$RU"
assert_ne 'proxy_it' "$IT"     'proxy_ru' "$RU"

echo '=== Verify: QUIC routing ==='
if "$CURL_HTTP3" --http3 -V >/dev/null 2>&1; then
    QUIC_IT=$("$CURL_HTTP3" -s --http3 --max-time 10 "$PROXY_IT_TEST_URL" | tr -d '[:space:]')
    QUIC_RU=$("$CURL_HTTP3" -s --http3 --max-time 10 "$PROXY_RU_TEST_URL" | tr -d '[:space:]')
    assert_nonempty 'eth0.me QUIC'  "$QUIC_IT"
    assert_nonempty 'ident.me QUIC' "$QUIC_RU"
    [[ "$QUIC_IT" == "$IT" ]] || { echo "FAIL: QUIC proxy_it ($QUIC_IT) != TLS ($IT)" >&2; exit 1; }
    [[ "$QUIC_RU" == "$RU" ]] || { echo "FAIL: QUIC proxy_ru ($QUIC_RU) != TLS ($RU)" >&2; exit 1; }
    echo "  QUIC matches TLS for both proxies"
else
    echo "  QUIC tests skipped ($CURL_HTTP3 lacks --http3)"
fi

echo '=== Verify: DNS sanity ==='
RESOLVED=$(eval "$DNS_CHECK_CMD")
[[ -n "$RESOLVED" ]] || { echo "FAIL: DNS sanity check returned empty" >&2; exit 1; }
echo "  checkip.amazonaws.com -> $RESOLVED"

echo '=== Verify: rule-set integrity ==='
expected=$(python3 - <<'PY'
import os, sys
sys.path.insert(0, 'shared')
from proxies_conf import all_of_kind, load
d = load('proxies.conf')
for c in all_of_kind(d, 'geosites'): print(f'geosite-{c}.json')
for c in all_of_kind(d, 'geoips'):   print(f'geoip-{c}.json')
PY
)
actual=$(cd "$RULE_SET_DIR" 2>/dev/null && ls -1 2>/dev/null | sort)
expected_sorted=$(echo "$expected" | sort)
diff_out=$(diff <(echo "$expected_sorted") <(echo "$actual") || true)
[[ -z "$diff_out" ]] || { echo "FAIL: rule-set dir mismatch:" >&2; echo "$diff_out" >&2; exit 1; }
for f in $expected; do
    [[ -s "$RULE_SET_DIR/$f" ]] || { echo "FAIL: $RULE_SET_DIR/$f empty" >&2; exit 1; }
done
echo "  $(echo "$expected" | wc -l | tr -d ' ') rule-sets match proxies.conf"

echo '=== Verify: no IPv6 leak ==='
v6=$(curl -6 -s --max-time 3 https://api64.ipify.org 2>/dev/null || true)
[[ -z "$v6" ]] || { echo "FAIL: IPv6 leak: $v6" >&2; exit 1; }
echo '  no IPv6 egress (IPv4-only constraint holds)'

if [[ -n "${ADD_DOMAIN:-}" && -n "${REMOVE_DOMAIN:-}" ]]; then
    echo '=== Verify: add-domain round-trip ==='
    RT_DOMAIN=httpbin.org
    RT_BEFORE=$(curl -s --max-time 10 https://$RT_DOMAIN/ip | python3 -c 'import json,sys;print(json.load(sys.stdin)["origin"])' 2>/dev/null || true)
    [[ -n "$RT_BEFORE" ]] || { echo "FAIL: $RT_DOMAIN unreachable pre-add" >&2; exit 1; }
    NO_GIT=1 $ADD_DOMAIN "$RT_DOMAIN" proxy_it
    sleep 3
    RT_AFTER=$(curl -s --max-time 10 https://$RT_DOMAIN/ip | python3 -c 'import json,sys;print(json.load(sys.stdin)["origin"])' 2>/dev/null || true)
    NO_GIT=1 $REMOVE_DOMAIN "$RT_DOMAIN"
    [[ -n "$RT_AFTER" ]] || { echo "FAIL: $RT_DOMAIN unreachable post-add" >&2; exit 1; }
    [[ "$RT_AFTER" == "$IT" ]] || { echo "FAIL: $RT_DOMAIN ($RT_AFTER) != proxy_it ($IT)" >&2; exit 1; }
    echo "  $RT_DOMAIN routed via proxy_it after add"
fi

if [[ -n "${SINGBOX_LOG:-}" && -f "$SINGBOX_LOG" ]]; then
    echo '=== Verify: log scan ==='
    suspicious=$(grep -E -i 'WARN|FATAL|panic' "$SINGBOX_LOG" || true)
    [[ -z "$suspicious" ]] || { echo "FAIL: log issues:" >&2; echo "$suspicious" >&2; exit 1; }
    echo '  log clean'
fi

echo '=== PASS ==='
