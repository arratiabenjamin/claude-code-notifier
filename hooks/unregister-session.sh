#!/usr/bin/env bash
# SessionEnd hook: mark the session as `ended` (with timestamp) instead of deleting it,
# so it stays visible in the SketchyBar popup until the TTL purge in cleanup-sessions.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/config.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json-helpers.sh"

input="$(cat 2>/dev/null || true)"
if [ -z "$input" ]; then
  exit 0
fi

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || echo '')"

if [ -z "$session_id" ]; then
  log "unregister-session: empty session_id"
  exit 0
fi

now_iso="$(date -u +%FT%TZ)"

_do_mark_ended() {
  ensure_state_file || return 1
  jq_mutate '
    if .sessions[$sid] then
      .sessions[$sid].status = "ended"
      | .sessions[$sid].ended_at = $now
      | .updated_at = $now
    else
      .
    end
  ' \
    --arg sid "$session_id" \
    --arg now "$now_iso" || {
      log "unregister-session: jq_mutate failed for sid=$session_id"
      return 1
    }
  return 0
}

if with_lock _do_mark_ended; then
  log "unregister-session: marked ended sid=$session_id"
else
  log "unregister-session: with_lock returned error"
fi

if [ -n "$SKETCHYBAR_BIN" ] && [ -x "$SKETCHYBAR_BIN" ]; then
  "$SKETCHYBAR_BIN" --trigger claude_done >/dev/null 2>&1 || true
fi

exit 0
