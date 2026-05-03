#!/bin/bash
cd "$(dirname "$0")/.."
source linux/common.sh
assert_root "$@"
exec systemctl status "$SERVICE_NAME" --no-pager
