#!/bin/bash
cd "$(dirname "$0")/.."
source linux/common.sh
assert_root "$@"
exec journalctl -u "$SERVICE_NAME" -f
