#!/usr/bin/env bash
# JSON helpers + atomic locking for STATE_FILE.
# Requires config.sh to be sourced first.

# ensure_state_file: guarantee a valid STATE_FILE. If corrupt or missing,
# back it up as .broken-<ts> and create a fresh empty one.
ensure_state_file() {
  mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
  if [ ! -f "$STATE_FILE" ]; then
    printf '{"version":1,"updated_at":"%s","sessions":{}}\n' \
      "$(date -u +%FT%TZ)" > "$STATE_FILE"
    return 0
  fi
  if ! jq -e . "$STATE_FILE" >/dev/null 2>&1; then
    local ts backup
    ts="$(date -u +%Y%m%d%H%M%S)"
    backup="${STATE_FILE}.broken-${ts}"
    log "STATE_FILE corrupted, moving to ${backup}"
    mv "$STATE_FILE" "$backup" 2>/dev/null || true
    printf '{"version":1,"updated_at":"%s","sessions":{}}\n' \
      "$(date -u +%FT%TZ)" > "$STATE_FILE"
  fi
  return 0
}

# with_lock <fn> [args...]: atomic lock via mkdir, max 5s.
# Trap guarantees the lock is always released.
with_lock() {
  local fn="$1"; shift
  local i=0
  local got_lock=0
  while [ "$i" -lt 50 ]; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      got_lock=1
      break
    fi
    sleep 0.1
    i=$((i + 1))
  done
  if [ "$got_lock" -ne 1 ]; then
    log "WARN: could not acquire lock after 5s ($LOCK_DIR)"
    return 1
  fi
  # Trap only inside this function scope to avoid clobbering outer traps.
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM
  local rc=0
  "$fn" "$@" || rc=$?
  rmdir "$LOCK_DIR" 2>/dev/null || true
  trap - EXIT INT TERM
  return "$rc"
}

# jq_mutate <expr> [--arg k v ...] [--argjson k v ...]
# Read STATE_FILE, apply filter, write atomically via mktemp+mv.
# First arg is the filter; the rest are jq arguments.
jq_mutate() {
  local expr="$1"; shift
  local tmp
  tmp="$(mktemp "${STATE_FILE}.XXXXXX")" || {
    log "ERR: mktemp failed"
    return 1
  }
  if jq -e "$@" "$expr" "$STATE_FILE" > "$tmp" 2>>"$LOG_FILE"; then
    mv "$tmp" "$STATE_FILE"
    return 0
  else
    rm -f "$tmp"
    log "ERR: jq_mutate failed with expr: $expr"
    return 1
  fi
}
