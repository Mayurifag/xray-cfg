#!/bin/bash
# Sourced by every platform's setup/test script.
# Each URL echoes the caller's source IP so we can identify which outbound was used.
DIRECT_TEST_URL=https://checkip.amazonaws.com
PROXY_IT_TEST_URL=https://eth0.me
PROXY_RU_TEST_URL=https://ident.me
ALL_TEST_URLS=("$DIRECT_TEST_URL" "$PROXY_IT_TEST_URL" "$PROXY_RU_TEST_URL")
