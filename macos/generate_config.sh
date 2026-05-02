#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source macos/common.sh
exec bash shared/generate_config.sh
