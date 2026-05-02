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

echo '=== PASS ==='
