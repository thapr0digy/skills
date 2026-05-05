#!/usr/bin/env bash
# Toggle tmux window name to indicate Claude Code is waiting on user input.
# Usage: tmux-claude-waiting.sh on|off
#
# Marker name itself ("⚠ CLAUDE") is the state indicator. If the visible name
# isn't the marker, "on" captures the current name + automatic-rename setting
# and renames. "off" only restores if the marker is currently visible. This
# is robust against manual `tmux rename-window` while Claude is waiting.

set -u

MARKER='⚠ CLAUDE'

action="${1:-}"
pane="${TMUX_PANE:-}"

[ -z "$pane" ] && exit 0
command -v tmux >/dev/null 2>&1 || exit 0

current_name=$(tmux display-message -t "$pane" -p '#W' 2>/dev/null || echo "")

case "$action" in
  on)
    if [ "$current_name" != "$MARKER" ]; then
      orig_auto=$(tmux show-window-options -t "$pane" -v automatic-rename 2>/dev/null || echo "on")
      tmux set-window-option -t "$pane" @claude_orig_name "$current_name" >/dev/null 2>&1
      tmux set-window-option -t "$pane" @claude_orig_auto "$orig_auto" >/dev/null 2>&1
    fi
    tmux set-window-option -t "$pane" automatic-rename off >/dev/null 2>&1
    tmux rename-window -t "$pane" "$MARKER" >/dev/null 2>&1
    ;;
  off)
    if [ "$current_name" = "$MARKER" ]; then
      orig_name=$(tmux show-window-options -t "$pane" -v @claude_orig_name 2>/dev/null || true)
      orig_auto=$(tmux show-window-options -t "$pane" -v @claude_orig_auto 2>/dev/null || true)
      if [ -n "$orig_name" ]; then
        tmux rename-window -t "$pane" "$orig_name" >/dev/null 2>&1
        [ -n "$orig_auto" ] && tmux set-window-option -t "$pane" automatic-rename "$orig_auto" >/dev/null 2>&1
      fi
    fi
    tmux set-window-option -t "$pane" -u @claude_orig_name >/dev/null 2>&1
    tmux set-window-option -t "$pane" -u @claude_orig_auto >/dev/null 2>&1
    tmux set-window-option -t "$pane" -u @claude_waiting >/dev/null 2>&1
    ;;
esac

exit 0
