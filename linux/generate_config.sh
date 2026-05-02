#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source linux/common.sh
exec bash shared/generate_config.sh
