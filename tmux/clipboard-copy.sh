#!/usr/bin/env sh
# clipboard-copy.sh — copy tmux buffer to system clipboard
# Works on Wayland, X11 and macOS. Preserve trailing newlines in the buffer.
set -eu
buf_file="$(mktemp)"
trap 'rm -f "$buf_file"' 0
trap 'exit 1' HUP INT TERM
tmux save-buffer "$buf_file"
if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null 2>&1; then
    wl-copy < "$buf_file"
elif [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then
    xclip -in -selection clipboard < "$buf_file"
elif command -v pbcopy >/dev/null 2>&1; then
    pbcopy < "$buf_file"
else
    echo "clipboard-copy: no clipboard backend for this session (Wayland: wl-clipboard; X11: xclip; macOS: pbcopy)" >&2
    exit 1
fi
