#!/bin/bash
cd "$(dirname "$0")/.."
source linux/common.sh
exec sudo systemctl status "$SERVICE_NAME" --no-pager
