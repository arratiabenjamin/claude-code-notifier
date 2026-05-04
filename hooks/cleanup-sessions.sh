#!/usr/bin/env bash
# Standalone cleanup. Two passes:
#   1) Zombies (running/idle with dead PID) → marked as `ended` with ended_at = now.
#   2) Sessions in `ended` whose ended_at is older than CLAUDE_ENDED_TTL (default 1h) → deleted.
# Called by the SketchyBar plugin before reading.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/config.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json-helpers.sh"

# TTL for sessions already marked `ended` (seconds). Default: 1 hour.
ENDED_TTL_SECONDS="${CLAUDE_ENDED_TTL:-3600}"

# If no state file, nothing to clean.
[ -f "$STATE_FILE" ] || exit 0

now_iso="$(date -u +%FT%TZ)"
now_epoch="$(date +%s)"

# Convert ISO8601 UTC (...Z) to epoch using BSD date. 0 on failure.
_iso_to_epoch() {
  local ts="$1"
  if [ -z "$ts" ] || [ "$ts" = "null" ]; then echo 0; return; fi
  date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo 0
}

_do_cleanup() {
  ensure_state_file || return 1
  if ! jq -e . "$STATE_FILE" >/dev/null 2>&1; then
    return 0
  fi

  local zombies_marked=0
  local purged=0
  local sids sid pid ended_at ended_epoch age

  # Pass 1: zombies (running/idle with dead PID) → mark as ended.
  sids="$(jq -r '
    .sessions
    | to_entries[]
    | select(.value.status == "running" or .value.status == "idle")
    | .key
  ' "$STATE_FILE" 2>/dev/null || echo '')"
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    pid="$(jq -r --arg s "$sid" '.sessions[$s].pid // empty' "$STATE_FILE" 2>/dev/null || echo '')"
    if [ -n "$pid" ] && [ "$pid" != "null" ] && [ "$pid" != "0" ]; then
      if ! kill -0 "$pid" 2>/dev/null; then
        if jq_mutate '
          if .sessions[$sid] then
            .sessions[$sid].status = "ended"
            | .sessions[$sid].ended_at = $now
            | .updated_at = $now
          else . end
        ' --arg sid "$sid" --arg now "$now_iso"; then
          zombies_marked=$((zombies_marked + 1))
        fi
      fi
    fi
  done <<< "$sids"

  # Pass 2: sessions in `ended` past TTL → del().
  sids="$(jq -r '
    .sessions
    | to_entries[]
    | select(.value.status == "ended")
    | .key
  ' "$STATE_FILE" 2>/dev/null || echo '')"
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    ended_at="$(jq -r --arg s "$sid" '.sessions[$s].ended_at // empty' "$STATE_FILE" 2>/dev/null || echo '')"
    [ -z "$ended_at" ] && continue
    ended_epoch="$(_iso_to_epoch "$ended_at")"
    [ "$ended_epoch" -le 0 ] && continue
    age=$((now_epoch - ended_epoch))
    if [ "$age" -gt "$ENDED_TTL_SECONDS" ]; then
      if jq_mutate 'del(.sessions[$sid]) | .updated_at = $now' \
                   --arg sid "$sid" --arg now "$now_iso"; then
        purged=$((purged + 1))
      fi
    fi
  done <<< "$sids"

  if [ "$zombies_marked" -gt 0 ] || [ "$purged" -gt 0 ]; then
    log "cleanup: zombies→ended=${zombies_marked}, purged=${purged}"
  fi
  return 0
}

with_lock _do_cleanup || log "cleanup-sessions: with_lock returned error"

exit 0
