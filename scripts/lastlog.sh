#!/usr/bin/env bash
# lastlog — print the most recent HalCode session log.
#
# Usage:
#   lastlog           # print path + tail the newest log
#   lastlog -p        # print the path only
#   lastlog -f        # follow (tail -f) the newest log
#   lastlog -n 200    # show the last N lines (default 50)
#
# Searches (newest wins):
#   ~/.halcode/logs/session_*.txt    headless/TUI full transcripts
#   ~/.halcode/chat_current.ndjson   live GTK chat
#   ~/.halcode/chat_*.ndjson         rotated GTK chats
#
# Copyright 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.

set -euo pipefail

HC="$HOME/.halcode"
LOG_DIR="$HC/logs"

show_path=0
follow=0
tail_n=50

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--path)   show_path=1; shift ;;
        -f|--follow) follow=1;   shift ;;
        -n)          tail_n="$2"; shift 2 ;;
        -h|--help)   sed -n '2,8p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "lastlog: unknown arg: $1 (try --help)" >&2; exit 2 ;;
    esac
done

latest=""
for f in "$LOG_DIR"/session_*.txt "$HC"/chat_current.ndjson "$HC"/chat_*.ndjson; do
    [[ -e "$f" ]] || continue
    if [[ -z "$latest" || "$f" -nt "$latest" ]]; then
        latest="$f"
    fi
done

if [[ -z "$latest" ]]; then
    echo "lastlog: no logs found under $HC" >&2
    exit 1
fi

if [[ "$show_path" -eq 1 ]]; then
    echo "$latest"
    exit 0
fi

echo "lastlog: $latest"
if [[ "$follow" -eq 1 ]]; then
    tail -n "$tail_n" -f "$latest"
else
    tail -n "$tail_n" "$latest"
fi
