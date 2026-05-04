#!/usr/bin/env bash
# UserPromptSubmit hook: mark the start of a turn (status=running).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/config.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json-helpers.sh"

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
  log "mark-prompt-start: empty session_id"
  exit 0
fi

pid="$PPID"
project_label="$(basename "${cwd:-/}")"
now="$(date -u +%FT%TZ)"

_do_mark() {
  ensure_state_file || return 1
  # If the session does not exist, create it defensively. Then set
  # prompt_started_at + status.
  jq_mutate '
    .updated_at = $now
    | .sessions[$sid] = (
        (.sessions[$sid] // {
          session_id: $sid,
          pid: ($pid | tonumber),
          cwd: $cwd,
          project_label: $label,
          started_at: $now
        })
        + {
            prompt_started_at: $now,
            status: "running"
          }
      )
  ' \
    --arg sid "$session_id" \
    --arg pid "$pid" \
    --arg cwd "${cwd:-}" \
    --arg label "$project_label" \
    --arg now "$now" || {
      log "mark-prompt-start: jq_mutate failed for sid=$session_id"
      return 1
    }
  return 0
}

with_lock _do_mark || log "mark-prompt-start: with_lock returned error"

if [ -n "$SKETCHYBAR_BIN" ] && [ -x "$SKETCHYBAR_BIN" ]; then
  "$SKETCHYBAR_BIN" --trigger claude_done >/dev/null 2>&1 || true
fi

exit 0
