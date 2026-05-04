#!/usr/bin/env bash
# Refresh of the Claude item: counts active sessions and paints color by state.
set -u

STATE_FILE="${HOME}/.claude/active-sessions.json"
CLEANUP="${HOME}/.claude/scripts/notifier/cleanup-sessions.sh"

# Sweep zombies before reading (best-effort).
if [ -x "$CLEANUP" ]; then
  "$CLEANUP" >/dev/null 2>&1 || true
fi

color_grey="0xff666666"
color_green="0xff44cc44"
color_yellow="0xffeebb22"

if [ ! -f "$STATE_FILE" ] || ! jq -e . "$STATE_FILE" >/dev/null 2>&1; then
  sketchybar --set claude label="0" background.color="$color_grey" 2>/dev/null || true
  exit 0
fi

count="$(jq '.sessions | length' "$STATE_FILE" 2>/dev/null || echo 0)"
running="$(jq '[.sessions[] | select(.status=="running")] | length' "$STATE_FILE" 2>/dev/null || echo 0)"

if [ "$running" -gt 0 ]; then
  color="$color_yellow"
elif [ "$count" -gt 0 ]; then
  color="$color_green"
else
  color="$color_grey"
fi

sketchybar --set claude label="$count" background.color="$color" 2>/dev/null || true
exit 0
