#!/usr/bin/env bash
# Click handler: toggle popup with two sections — ACTIVE + RECENTLY COMPLETED sessions.
set -u

STATE_FILE="$HOME/.claude/active-sessions.json"

# Toggle: if the popup is already drawn, close it and exit.
current="$(sketchybar --query claude 2>/dev/null | jq -r '.popup.drawing // "off"' 2>/dev/null || echo off)"
if [ "$current" = "on" ]; then
  sketchybar --set claude popup.drawing=off 2>/dev/null || true
  exit 0
fi

# Clear previous popup items (recreate fresh every open).
existing="$(sketchybar --query bar 2>/dev/null \
  | jq -r '.items[]?' 2>/dev/null \
  | grep -E '^claude\.popup\.' || true)"
if [ -n "$existing" ]; then
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    sketchybar --remove "$item" >/dev/null 2>&1 || true
  done <<< "$existing"
fi

# No state file → "no sessions" placeholder.
if [ ! -f "$STATE_FILE" ] || ! jq -e . "$STATE_FILE" >/dev/null 2>&1; then
  sketchybar --add item claude.popup.empty popup.claude \
             --set claude.popup.empty label="No sessions yet" \
                                       label.color=0xff888888 \
                                       icon="·" \
                                       icon.color=0xff888888 \
                                       background.drawing=off 2>/dev/null || true
  sketchybar --set claude popup.drawing=on 2>/dev/null || true
  exit 0
fi

# Helper: format ISO8601 UTC timestamp as relative time ("12s ago", "3m ago", "1h ago").
fmt_ago() {
  local ts="$1"
  if [ -z "$ts" ] || [ "$ts" = "null" ]; then
    echo "—"
    return
  fi
  local epoch_then now diff
  epoch_then="$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo 0)"
  if [ "$epoch_then" -le 0 ]; then
    echo "—"
    return
  fi
  now="$(date +%s)"
  diff=$((now - epoch_then))
  if [ "$diff" -lt 60 ]; then
    echo "${diff}s ago"
  elif [ "$diff" -lt 3600 ]; then
    echo "$((diff / 60))m ago"
  else
    echo "$((diff / 3600))h ago"
  fi
}

# Sanitize a session id for use as a SketchyBar item name.
sanitize() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9-' '_'
}

active_count="$(jq '[.sessions[] | select(.status=="running" or .status=="idle")] | length' "$STATE_FILE" 2>/dev/null || echo 0)"
ended_count="$(jq '[.sessions[] | select(.status=="ended")] | length' "$STATE_FILE" 2>/dev/null || echo 0)"

# === ACTIVE SECTION ===
if [ "$active_count" -gt 0 ]; then
  sketchybar --add item claude.popup.hdr_active popup.claude \
             --set claude.popup.hdr_active label="ACTIVE" \
                                            label.font="SF Pro:Bold:10.0" \
                                            label.color=0xff44cc44 \
                                            icon=" " \
                                            background.drawing=off 2>/dev/null || true

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    sid="$(printf '%s' "$entry" | jq -r '.key' 2>/dev/null || echo '')"
    [ -z "$sid" ] && continue
    safe="$(sanitize "$sid")"
    proj="$(printf '%s' "$entry" | jq -r '.value.project_label // "(unknown)"' 2>/dev/null || echo '(unknown)')"
    status="$(printf '%s' "$entry" | jq -r '.value.status // "idle"' 2>/dev/null || echo 'idle')"
    started="$(printf '%s' "$entry" | jq -r '.value.prompt_started_at // .value.started_at // empty' 2>/dev/null || echo '')"
    when="$(fmt_ago "$started")"

    if [ "$status" = "running" ]; then
      icon="●"
    else
      icon="○"
    fi

    sketchybar --add item "claude.popup.a_${safe}" popup.claude \
               --set "claude.popup.a_${safe}" \
                          label="${proj} · ${status} · ${when}" \
                          icon="$icon" \
                          icon.color=0xff44cc44 \
                          background.drawing=off 2>/dev/null || true
  done < <(jq -c '.sessions | to_entries[] | select(.value.status=="running" or .value.status=="idle")' "$STATE_FILE" 2>/dev/null || echo '')
fi

# === RECENTLY COMPLETED SECTION ===
if [ "$ended_count" -gt 0 ]; then
  sketchybar --add item claude.popup.hdr_ended popup.claude \
             --set claude.popup.hdr_ended label="RECENTLY COMPLETED" \
                                           label.font="SF Pro:Bold:10.0" \
                                           label.color=0xff888888 \
                                           icon=" " \
                                           background.drawing=off 2>/dev/null || true

  # Cap at 10 most recent ended entries to avoid flooding the popup.
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    sid="$(printf '%s' "$entry" | jq -r '.key' 2>/dev/null || echo '')"
    [ -z "$sid" ] && continue
    safe="$(sanitize "$sid")"
    proj="$(printf '%s' "$entry" | jq -r '.value.project_label // "(unknown)"' 2>/dev/null || echo '(unknown)')"
    last_dur="$(printf '%s' "$entry" | jq -r '.value.last_turn_duration_s // 0' 2>/dev/null || echo 0)"
    ended_at="$(printf '%s' "$entry" | jq -r '.value.ended_at // .value.last_turn_finished_at // empty' 2>/dev/null || echo '')"
    when="$(fmt_ago "$ended_at")"

    sketchybar --add item "claude.popup.e_${safe}" popup.claude \
               --set "claude.popup.e_${safe}" \
                          label="${proj} · ${last_dur}s · ${when}" \
                          icon="✓" \
                          icon.color=0xff888888 \
                          label.color=0xffaaaaaa \
                          background.drawing=off 2>/dev/null || true
  done < <(jq -c '.sessions | to_entries
                 | map(select(.value.status=="ended"))
                 | sort_by(.value.ended_at // .value.last_turn_finished_at // "")
                 | reverse
                 | .[]' "$STATE_FILE" 2>/dev/null | head -10)
fi

# Empty state.
if [ "$active_count" -eq 0 ] && [ "$ended_count" -eq 0 ]; then
  sketchybar --add item claude.popup.empty popup.claude \
             --set claude.popup.empty label="No sessions" \
                                       label.color=0xff888888 \
                                       icon="·" \
                                       icon.color=0xff888888 \
                                       background.drawing=off 2>/dev/null || true
fi

sketchybar --set claude popup.drawing=on 2>/dev/null || true
exit 0
