#!/usr/bin/env bash
# Stage a HalCode-Haiku compile directory with generated platform selectors.
# The tracked Platform/*.ailang files are not modified.
#
# Usage:
#   scripts/stage_platform.sh linux|haiku /tmp/some-stage [tui|headless]
#
# linux   copies the tracked Linux selector files.
# haiku   writes selectors that import the *Haiku modules.
# tui     points UI.ailang at the shared HalCode9000 TUI (agent compile).
# headless points UI.ailang at this tree's stand-in. Default is tui.
#
# Copyright 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 linux|haiku /tmp/stage-dir [tui|headless]" >&2
    exit 2
fi

OS="$1"
STAGE="$2"
UI_KIND="${3:-tui}"

case "$OS" in
    linux|haiku) ;;
    *) echo "platform must be linux or haiku" >&2; exit 2 ;;
esac
case "$UI_KIND" in
    tui|headless) ;;
    *) echo "ui must be tui or headless" >&2; exit 2 ;;
esac
case "$STAGE" in
    /tmp/*) ;;
    *) echo "stage directory must be under /tmp" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELECTORS=(Proc IPC HTTP Fan Agent Signal AilangRun)

if [[ "$UI_KIND" == tui && ! -f /home/bob/HalCode9000/UI.ailang ]]; then
    echo "shared TUI missing: /home/bob/HalCode9000/UI.ailang" >&2
    exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE/Platform" "$STAGE/Applications"

for item in "$ROOT"/*; do
    base="$(basename "$item")"
    case "$base" in
        Platform|Applications|UI.ailang) continue ;;
    esac
    ln -s "$item" "$STAGE/$base"
done

for src in "$ROOT"/Platform/*; do
    base="$(basename "$src")"
    is_selector=0
    for name in "${SELECTORS[@]}"; do
        if [[ "$base" == "${name}.ailang" ]]; then
            is_selector=1
        fi
    done
    if [[ "$is_selector" -eq 0 ]]; then
        ln -s "$src" "$STAGE/Platform/$base"
    fi
done

for name in "${SELECTORS[@]}"; do
    dest="$STAGE/Platform/${name}.ailang"
    if [[ "$OS" == linux ]]; then
        cp -a "$ROOT/Platform/${name}.ailang" "$dest"
    else
        printf '%s\n' \
            "// Generated for the Haiku build. The tracked selector is unchanged." \
            "// Copyright 2026 Sean Collins, 2 Paws Machine and Engineering. MIT." \
            "" \
            "Import.Platform.${name}Haiku" \
            > "$dest"
    fi
done

if [[ "$UI_KIND" == tui ]]; then
    ln -s /home/bob/HalCode9000/UI.ailang "$STAGE/UI.ailang"
else
    ln -s "$ROOT/UI.ailang" "$STAGE/UI.ailang"
fi
ln -s "$STAGE" "$STAGE/Applications/HalCode9000"

echo "$STAGE"
