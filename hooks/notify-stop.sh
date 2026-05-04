#!/usr/bin/env bash
# Stop hook: close the turn, compute duration, decide whether to notify.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/config.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json-helpers.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/notify.sh"

if [ -f "$DISABLE_FLAG" ]; then
  exit 0
fi

input="$(cat 2>/dev/null || true)"
if [ -z "$input" ]; then
  exit 0
fi

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || echo '')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || echo '')"

if [ -z "$session_id" ]; then
  log "notify-stop: empty session_id"
  exit 0
fi

# Convert ISO8601 UTC (...Z) to epoch using BSD date. 0 on failure.
_iso_to_epoch() {
  local ts="$1"
  if [ -z "$ts" ]; then echo 0; return; fi
  date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo 0
}

# Read prompt_started_at before mutating, so we can compute duration.
prompt_started_at=""
if [ -f "$STATE_FILE" ] && jq -e . "$STATE_FILE" >/dev/null 2>&1; then
  prompt_started_at="$(jq -r --arg sid "$session_id" \
    '.sessions[$sid].prompt_started_at // empty' "$STATE_FILE" 2>/dev/null || echo '')"
fi

now_iso="$(date -u +%FT%TZ)"
now_epoch="$(_iso_to_epoch "$now_iso")"
start_epoch="$(_iso_to_epoch "$prompt_started_at")"

if [ "$start_epoch" -gt 0 ] && [ "$now_epoch" -gt 0 ]; then
  duration=$((now_epoch - start_epoch))
  [ "$duration" -lt 0 ] && duration=0
else
  duration=0
fi

_do_close() {
  ensure_state_file || return 1
  # Update status + duration + finished_at
  jq_mutate '
    .updated_at = $now
    | .sessions[$sid] = (
        (.sessions[$sid] // {})
        + {
            status: "idle",
            last_turn_duration_s: ($dur | tonumber),
            last_turn_finished_at: $now,
            last_result: "ok"
          }
      )
  ' \
    --arg sid "$session_id" \
    --arg now "$now_iso" \
    --arg dur "$duration" || {
      log "notify-stop: jq_mutate (close) failed for sid=$session_id"
      return 1
    }

  # Inline cleanup: mark sessions whose PID no longer exists as `ended`
  # (instead of deleting them, so they remain visible in the popup until TTL).
  # We iterate in bash because kill -0 cannot run inside jq.
  if [ -f "$STATE_FILE" ] && jq -e . "$STATE_FILE" >/dev/null 2>&1; then
    local sids
    sids="$(jq -r '
      .sessions
      | to_entries[]
      | select(.value.status == "running" or .value.status == "idle")
      | .key
    ' "$STATE_FILE" 2>/dev/null || echo '')"
    local sid pid
    while IFS= read -r sid; do
      [ -z "$sid" ] && continue
      pid="$(jq -r --arg s "$sid" '.sessions[$s].pid // empty' "$STATE_FILE" 2>/dev/null || echo '')"
      if [ -n "$pid" ] && [ "$pid" != "null" ] && [ "$pid" != "0" ]; then
        if ! kill -0 "$pid" 2>/dev/null; then
          jq_mutate '
            if .sessions[$sid] then
              .sessions[$sid].status = "ended"
              | .sessions[$sid].ended_at = $now
              | .updated_at = $now
            else . end
          ' \
            --arg sid "$sid" \
            --arg now "$now_iso" || true
        fi
      fi
    done <<< "$sids"
  fi
  return 0
}

with_lock _do_close || log "notify-stop: with_lock returned error"

# After the lock: re-read fresh state to decide whether to notify.
active=0
project_label=""
if [ -f "$STATE_FILE" ] && jq -e . "$STATE_FILE" >/dev/null 2>&1; then
  active="$(jq '[.sessions[] | select(.status=="running" or .status=="idle")] | length' "$STATE_FILE" 2>/dev/null || echo 0)"
  project_label="$(jq -r --arg sid "$session_id" \
    '.sessions[$sid].project_label // empty' "$STATE_FILE" 2>/dev/null || echo '')"
fi

# Fall back to stdin cwd if no label was found in state (session already cleaned).
if [ -z "$project_label" ]; then
  project_label="$(basename "${cwd:-Claude}")"
fi

should_notify=0
if [ "$duration" -gt "$THRESHOLD_SECONDS" ]; then
  should_notify=1
fi
if [ "$active" -gt 1 ]; then
  should_notify=1
fi

if [ "$should_notify" -eq 1 ]; then
  msg="${project_label} · ${duration}s · ${active} sessions"
  notify_user "Claude Code" "$msg" "claude-${session_id}"
  log "notify-stop: notified sid=$session_id dur=${duration}s active=${active}"
else
  log "notify-stop: skip sid=$session_id dur=${duration}s active=${active} threshold=${THRESHOLD_SECONDS}"
fi

if [ -n "$SKETCHYBAR_BIN" ] && [ -x "$SKETCHYBAR_BIN" ]; then
  "$SKETCHYBAR_BIN" --trigger claude_done >/dev/null 2>&1 || true
fi

exit 0
