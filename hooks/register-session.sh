#!/usr/bin/env bash
# SessionStart hook: register a fresh session into the state file.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/config.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json-helpers.sh"

# Disabled flag -> exit silently
if [ -f "$DISABLE_FLAG" ]; then
  exit 0
fi

input="$(cat 2>/dev/null || true)"
if [ -z "$input" ]; then
  log "register-session: empty stdin"
  exit 0
fi

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || echo '')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || echo '')"
transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || echo '')"

if [ -z "$session_id" ] || [ -z "$cwd" ]; then
  log "register-session: empty session_id or cwd"
  exit 0
fi

pid="$PPID"
project_label="$(basename "$cwd")"
now="$(date -u +%FT%TZ)"

_do_register() {
  ensure_state_file || return 1
  # Upsert: if the session already exists (resume), preserve started_at; else create it.
  jq_mutate '
    .updated_at = $now
    | .sessions[$sid] = (
        (.sessions[$sid] // {})
        + {
            session_id: $sid,
            pid: ($pid | tonumber),
            cwd: $cwd,
            project_label: $label,
            started_at: ((.sessions[$sid] // {}).started_at // $now),
            status: "idle",
            transcript_path: $tp
          }
      )
  ' \
    --arg sid "$session_id" \
    --arg pid "$pid" \
    --arg cwd "$cwd" \
    --arg label "$project_label" \
    --arg now "$now" \
    --arg tp "$transcript_path" || {
      log "register-session: jq_mutate failed for sid=$session_id"
      return 1
    }
  return 0
}

with_lock _do_register || log "register-session: with_lock returned error"

if [ -n "$SKETCHYBAR_BIN" ] && [ -x "$SKETCHYBAR_BIN" ]; then
  "$SKETCHYBAR_BIN" --trigger claude_done >/dev/null 2>&1 || true
fi

exit 0
