#!/usr/bin/env bash
# Notifier configuration - sourced by every hook script.
# Does NOT use `set -e` (hooks must never crash the parent). `set -u` is
# applied by the caller.

export STATE_FILE="${HOME}/.claude/active-sessions.json"
export LOCK_DIR="${HOME}/.claude/active-sessions.lock"
export DISABLE_FLAG="${HOME}/.claude/notifier-disabled"
export LOG_FILE="${HOME}/.claude/scripts/notifier/notifier.log"
export THRESHOLD_SECONDS="${CLAUDE_NOTIFY_THRESHOLD:-90}"
NOTIFIER_BIN="$(command -v terminal-notifier 2>/dev/null || echo '')"
SKETCHYBAR_BIN="$(command -v sketchybar 2>/dev/null || echo '')"
export NOTIFIER_BIN
export SKETCHYBAR_BIN

# Logger with trivial rotation (>1MB -> .old)
log() {
  local msg
  msg="[$(date -u +%FT%TZ)] $*"
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  if [ -f "$LOG_FILE" ]; then
    local size
    size="$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)"
    if [ "$size" -gt 1048576 ]; then
      mv "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
    fi
  fi
  echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}
