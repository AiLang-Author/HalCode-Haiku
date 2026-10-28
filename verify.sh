#!/usr/bin/env bash
# verify.sh — one-shot build verification across both HalCode trees.
#
# Usage:
#   ./verify.sh [SYMBOL]         grep both trees for SYMBOL, then fast-compile both
#   ./verify.sh --build          compile both trees (main binary only, fast)
#   ./verify.sh --full [SYMBOL]  full build (tools + main) of both trees
#   ./verify.sh --grep SYMBOL    grep both trees for SYMBOL only
#
# The two trees are this repo (the GTK fork) and the canonical AILang source,
# resolved from the ailang.x compiler location via Applications/HalCode9000
# (a symlink to ~/HalCode9000). Compiles use --no-copy so nothing is installed
# — safe to run while the app is live. Exit 0 = all checks pass.
#
# Copyright 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- resolve the second tree ------------------------------------------------
AILANG="$(command -v ailang.x 2>/dev/null || true)"
OTHER=""
if [[ -n "$AILANG" ]]; then
    AILANG_ROOT="$(cd "$(dirname "$(readlink -f "$AILANG")")" && pwd)"
    OTHER="$(readlink -f "$AILANG_ROOT/Applications/HalCode9000" 2>/dev/null || true)"
fi
[[ -z "$OTHER" || ! -d "$OTHER" ]] && OTHER="$HOME/HalCode9000"

TREES=("$ROOT")
if [[ -d "$OTHER" && "$(readlink -f "$OTHER")" != "$(readlink -f "$ROOT")" ]]; then
    TREES+=("$(readlink -f "$OTHER")")
fi

# ---- arg parsing ------------------------------------------------------------
MODE=fast
SYMBOL=""
BUILD_FLAGS=(--no-tools --no-copy --quiet)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build) MODE=build; shift ;;
        --full)  MODE=full; BUILD_FLAGS=(--no-copy --quiet); shift ;;
        --grep)  MODE=grep;  shift ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) SYMBOL="$1"; shift ;;
    esac
done

DO_GREP=0; DO_BUILD=0
case "$MODE" in
    grep)  DO_GREP=1 ;;
    build) DO_BUILD=1 ;;
    full)  DO_BUILD=1; [[ -n "$SYMBOL" ]] && DO_GREP=1 ;;
    fast)  DO_BUILD=1; [[ -n "$SYMBOL" ]] && DO_GREP=1 ;;
esac

# ---- helpers ----------------------------------------------------------------
pass=0
fail=0
ok()  { printf '  [ok]   %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  [FAIL] %s\n' "$1" >&2; fail=$((fail+1)); }
label() { basename "$1"; }

echo "verify.sh: checking ${#TREES[@]} tree(s):"
for t in "${TREES[@]}"; do echo "  - $t"; done
echo ""

if [[ $DO_GREP -eq 1 ]]; then
    for t in "${TREES[@]}"; do
        n="$(grep -rIn --include='*.ailang' -F "$SYMBOL" "$t" 2>/dev/null | wc -l)"
        if [[ "$n" -eq 0 ]]; then
            ok "grep '$SYMBOL': 0 refs in $(label "$t")"
        else
            bad "grep '$SYMBOL': $n refs in $(label "$t")"
            grep -rIn --include='*.ailang' -F "$SYMBOL" "$t" 2>/dev/null | head -15 >&2 || true
        fi
    done
fi

if [[ $DO_BUILD -eq 1 ]]; then
    for t in "${TREES[@]}"; do
        if [[ ! -x "$t/build.sh" ]]; then
            bad "build $(label "$t"): build.sh missing"
            continue
        fi
        logf="/tmp/verify_build_$(label "$t").log"
        if (cd "$t" && ./build.sh "${BUILD_FLAGS[@]}") >"$logf" 2>&1; then
            ok "build $(label "$t")"
        else
            bad "build $(label "$t") (see $logf)"
            grep -iE "ERROR|FATAL|Failed" "$logf" | head -8 >&2 || true
        fi
    done
fi

echo ""
echo "verify.sh: ${pass} passed, ${fail} failed"
if [[ $fail -eq 0 ]]; then
    echo "verify.sh: PASS"
    exit 0
else
    echo "verify.sh: FAIL" >&2
    exit 1
fi
