#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec bash shared/doctor_core.sh
