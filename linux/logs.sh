#!/bin/bash
cd "$(dirname "$0")/.."
source linux/common.sh
exec sudo journalctl -u "$SERVICE_NAME" -f
