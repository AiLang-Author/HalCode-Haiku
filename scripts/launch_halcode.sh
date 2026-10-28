#!/usr/bin/env bash
# Start the Linux desk through the Haiku bridge, then the native window.
# Does not touch a HalCode9000.x --mcp process on the build machine.
#
# Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHELL_DIR="$ROOT/shell"
STATE="${HALCODE_APP_STATE:-/tmp/halcode_app}"
DESK="$SHELL_DIR/halcode_desk.x"
HOST="$SHELL_DIR/halcode_shell_haiku"
LOG="$STATE/launch.log"

if [[ -n "${SYS_COMPAT_RUN:-}" ]]; then
    RUNNER="$SYS_COMPAT_RUN"
elif command -v sys_compat_run >/dev/null 2>&1; then
    RUNNER="$(command -v sys_compat_run)"
else
    RUNNER=""
fi

[[ -x "$DESK" ]] || { echo "missing $DESK — make -C $SHELL_DIR desk" >&2; exit 1; }
[[ -x "$HOST" ]] || { echo "missing $HOST — on Haiku: make -C $SHELL_DIR" >&2; exit 1; }

mkdir -p "$STATE"
echo "---- $(date -Iseconds) launch_halcode ----" >> "$LOG"
if [[ -f "$ROOT/providers/picker.txt" ]]; then
    cp -f "$ROOT/providers/picker.txt" "$STATE/picker.txt"
fi

if [[ -f /tmp/halcode_desk.pid ]]; then
    kill "$(cat /tmp/halcode_desk.pid)" 2>/dev/null || true
fi
sleep 0.2
rm -f /tmp/halcode_desk.pid
: > "$STATE/cmd.txt"

export HALCODE_ROOT="$ROOT"
export HALCODE_APP_STATE="$STATE"
cd "$ROOT"
if [[ -n "$RUNNER" ]]; then
    echo "HalCode desk via $RUNNER"
    "$RUNNER" "$DESK" >>"$LOG" 2>&1 &
else
    echo "HalCode desk direct (no sys_compat_run on PATH)"
    "$DESK" >>"$LOG" 2>&1 &
fi
DESK_PID=$!
echo "$DESK_PID" > /tmp/halcode_desk.pid
cleanup() {
    kill "$DESK_PID" 2>/dev/null || true
    wait "$DESK_PID" 2>/dev/null || true
    rm -f /tmp/halcode_desk.pid
}
trap cleanup EXIT INT TERM
sleep 0.4
if ! kill -0 "$DESK_PID" 2>/dev/null; then
    echo "ERROR: halcode_desk.x exited — see $LOG" >&2
    tail -20 "$LOG" >&2 || true
    exit 1
fi
"$HOST" "$STATE"
