#!/usr/bin/env bash
# Helper to dispatch native macOS notifications.
# Requires config.sh to be sourced.

# notify_user "<title>" "<message>" "<group>"
notify_user() {
  local title="${1:-Claude Code}"
  local message="${2:-}"
  local group="${3:-claude-default}"

  if [ -n "$NOTIFIER_BIN" ] && [ -x "$NOTIFIER_BIN" ]; then
    "$NOTIFIER_BIN" \
      -title "$title" \
      -message "$message" \
      -group "$group" \
      -sound default >/dev/null 2>&1 || {
        log "WARN: terminal-notifier failed, falling back to osascript"
        _notify_osascript "$title" "$message"
      }
  else
    _notify_osascript "$title" "$message"
  fi
}

_notify_osascript() {
  local title="$1"
  local message="$2"
  # Escape double quotes and backslashes for AppleScript
  local esc_title esc_msg
  esc_title="${title//\\/\\\\}"
  esc_title="${esc_title//\"/\\\"}"
  esc_msg="${message//\\/\\\\}"
  esc_msg="${esc_msg//\"/\\\"}"
  osascript -e "display notification \"${esc_msg}\" with title \"${esc_title}\"" \
    >/dev/null 2>&1 || log "WARN: osascript notification failed"
}
