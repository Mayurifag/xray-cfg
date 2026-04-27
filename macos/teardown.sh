#!/bin/bash
# Tear down xray + sing-box TUN proxy on macOS, reversing setup.sh side effects.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

assert_root "$@"

write_phase teardown 'Phase 1: bootout LaunchDaemons'
for label in "${LABELS[@]}"; do
    if launchctl bootout "system/$label" 2>/dev/null; then
        write_phase teardown "  booted out $label"
    else
        write_phase teardown "  $label not loaded"
    fi
done

write_phase teardown 'Phase 2: remove plists'
for label in "${LABELS[@]}"; do
    rm -f "$LAUNCH_DAEMON_DIR/$label.plist"
done

write_phase teardown 'Phase 3: kill stragglers (TERM, escalate to KILL)'
pkill -TERM -x xray     2>/dev/null || true
pkill -TERM -x sing-box 2>/dev/null || true

# Wait up to 10s for processes to exit cleanly. sing-box can take several
# seconds to release the utun device and restore routes/DNS.
deadline=$(($(date +%s) + 10))
while (( $(date +%s) < deadline )); do
    pgrep -x xray >/dev/null || pgrep -x sing-box >/dev/null || break
    if ! pgrep -x xray >/dev/null && ! pgrep -x sing-box >/dev/null; then
        break
    fi
    sleep 1
done

# Anything still alive: SIGKILL
if pgrep -x xray >/dev/null || pgrep -x sing-box >/dev/null; then
    write_phase teardown '  TERM did not finish in 10s; escalating to KILL'
    pkill -KILL -x xray     2>/dev/null || true
    pkill -KILL -x sing-box 2>/dev/null || true
    sleep 1
fi

write_phase teardown 'Phase 4: wait for utun gone'
deadline=$(($(date +%s) + 5))
while (( $(date +%s) < deadline )); do
    if ! ifconfig | grep -qE 'inet 172\.18\.0\.1'; then
        break
    fi
    sleep 1
done

write_phase teardown 'Phase 5: verify clean'
dirty=()

if pgrep -x xray     >/dev/null; then dirty+=('xray process still running'); fi
if pgrep -x sing-box >/dev/null; then dirty+=('sing-box process still running'); fi
if ifconfig | grep -qE 'inet 172\.18\.0\.1'; then dirty+=('utun with 172.18.0.1 still present'); fi
for label in "${LABELS[@]}"; do
    if [[ -f "$LAUNCH_DAEMON_DIR/$label.plist" ]]; then
        dirty+=("plist for $label still in $LAUNCH_DAEMON_DIR")
    fi
done

rm -f "$PID_FILE"

if (( ${#dirty[@]} == 0 )); then
    echo "Teardown complete. System clean."
    exit 0
fi

echo "Teardown incomplete:"
for line in "${dirty[@]}"; do
    echo "  - $line"
done
exit 1
