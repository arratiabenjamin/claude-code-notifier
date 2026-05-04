#!/usr/bin/env bash
# Standalone cleanup: drop orphan sessions (dead PID) from the state.
# Called by the SketchyBar plugin before reading.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/config.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json-helpers.sh"

# If no state file, nothing to clean.
[ -f "$STATE_FILE" ] || exit 0

now_iso="$(date -u +%FT%TZ)"

_do_cleanup() {
  ensure_state_file || return 1
  if ! jq -e . "$STATE_FILE" >/dev/null 2>&1; then
    return 0
  fi
  local sids sid pid
  sids="$(jq -r '.sessions | keys[]' "$STATE_FILE" 2>/dev/null || echo '')"
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    pid="$(jq -r --arg s "$sid" '.sessions[$s].pid // empty' "$STATE_FILE" 2>/dev/null || echo '')"
    if [ -n "$pid" ] && [ "$pid" != "null" ] && [ "$pid" != "0" ]; then
      if ! kill -0 "$pid" 2>/dev/null; then
        jq_mutate 'del(.sessions[$sid]) | .updated_at = $now' \
          --arg sid "$sid" \
          --arg now "$now_iso" || true
      fi
    fi
  done <<< "$sids"
  return 0
}

with_lock _do_cleanup || log "cleanup-sessions: with_lock returned error"

exit 0
