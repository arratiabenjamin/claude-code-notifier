#!/usr/bin/env bash
# Refresh of the Claude item: counts active + recently-ended sessions, colors the pill.
set -u

STATE_FILE="$HOME/.claude/active-sessions.json"
CLEANUP="$HOME/.claude/scripts/notifier/cleanup-sessions.sh"

# Pill colors.
COLOR_GREY="0xff444444"      # nothing active, nothing recently ended
COLOR_GREEN="0xff2e7d32"     # one or more active sessions, none currently running
COLOR_AMBER="0xffe0a800"     # at least one session is currently running
COLOR_BLUE="0xff2c5aa0"      # only recently-ended sessions, nothing active

# Sweep zombies / purge old ended sessions before reading (best-effort).
if [ -x "$CLEANUP" ]; then
  "$CLEANUP" >/dev/null 2>&1 || true
fi

if [ ! -f "$STATE_FILE" ] || ! jq -e . "$STATE_FILE" >/dev/null 2>&1; then
  sketchybar --set claude label="0 · 0" \
                          icon="◆" \
                          background.color="$COLOR_GREY" 2>/dev/null || true
  exit 0
fi

active="$(jq '[.sessions[] | select(.status=="running" or .status=="idle")] | length' "$STATE_FILE" 2>/dev/null || echo 0)"
running="$(jq '[.sessions[] | select(.status=="running")] | length' "$STATE_FILE" 2>/dev/null || echo 0)"
ended="$(jq '[.sessions[] | select(.status=="ended")] | length' "$STATE_FILE" 2>/dev/null || echo 0)"

if [ "$running" -gt 0 ]; then
  color="$COLOR_AMBER"
elif [ "$active" -gt 0 ]; then
  color="$COLOR_GREEN"
elif [ "$ended" -gt 0 ]; then
  color="$COLOR_BLUE"
else
  color="$COLOR_GREY"
fi

# Label format: "ACTIVE · ENDED"  e.g. "2 · 5"
label="${active} · ${ended}"

sketchybar --set claude label="$label" \
                        icon="◆" \
                        background.color="$color" 2>/dev/null || true
exit 0
