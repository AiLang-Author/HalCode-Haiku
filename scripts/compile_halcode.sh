#!/usr/bin/env bash
# Compile HalCode9000 through a generated platform stage.
# Does not edit tracked selector files or this tree's UI.ailang.
#
# Usage:
#   scripts/compile_halcode.sh linux|haiku /tmp/out.x [tui|headless]
#
# Copyright 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 linux|haiku /tmp/out.x [tui|headless]" >&2
    exit 2
fi

OS="$1"
OUT="$2"
UI_KIND="${3:-tui}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC="${HALCODE_CC:-/tmp/c_new}"
STAGE="/tmp/hc_stage_${OS}_$$"

if [[ ! -x "$CC" ]]; then
    echo "compiler missing: $CC" >&2
    exit 1
fi

"$ROOT/scripts/stage_platform.sh" "$OS" "$STAGE" "$UI_KIND"
cleanup() {
    rm -rf "$STAGE"
}
trap cleanup EXIT

case "$OUT" in
    /*) ;;
    *) OUT="$(pwd)/$OUT" ;;
esac

extra=()
if [[ "$OS" == haiku ]]; then
    extra+=(--haiku)
fi

# Imports are resolved from the working directory. The stage holds the
# generated selectors and the Applications/HalCode9000 link.
cd "$STAGE"
AILANG_LIB_PATH="${AILANG_LIB_PATH:-/home/bob/Ailang-Self-Hosting-/Librarys}" \
    env -u AILANG_LINSCAN \
    "$CC" -march=sse2 "${extra[@]}" \
    HalCode9000.ailang "$OUT"
