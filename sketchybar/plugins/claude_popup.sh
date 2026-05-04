#!/usr/bin/env bash
# Click handler: toggle popup with the list of active sessions.
set -u

STATE_FILE="${HOME}/.claude/active-sessions.json"

# Clear previous popup items (we recreate them every click).
existing="$(sketchybar --query claude 2>/dev/null \
  | jq -r '.popup.items[]?' 2>/dev/null || echo '')"
if [ -n "$existing" ]; then
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    sketchybar --remove "$item" 2>/dev/null || true
  done <<< "$existing"
fi

# If no state file, render empty popup.
if [ ! -f "$STATE_FILE" ] || ! jq -e . "$STATE_FILE" >/dev/null 2>&1; then
  sketchybar --add item claude.popup.empty popup.claude \
             --set claude.popup.empty label="No active sessions" icon="·" \
    2>/dev/null || true
  sketchybar --set claude popup.drawing=toggle 2>/dev/null || true
  exit 0
fi

count="$(jq '.sessions | length' "$STATE_FILE" 2>/dev/null || echo 0)"

if [ "$count" -eq 0 ]; then
  sketchybar --add item claude.popup.empty popup.claude \
             --set claude.popup.empty label="No active sessions" icon="·" \
    2>/dev/null || true
else
  # Iterate sessions and create one popup item per session.
  i=0
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    sid="$(printf '%s' "$entry" | jq -r '.key' 2>/dev/null || echo '')"
    label="$(printf '%s' "$entry" | jq -r '.value.project_label // "(unknown)"' 2>/dev/null || echo '(unknown)')"
    status="$(printf '%s' "$entry" | jq -r '.value.status // "idle"' 2>/dev/null || echo 'idle')"
    dur="$(printf '%s' "$entry" | jq -r '.value.last_turn_duration_s // 0' 2>/dev/null || echo 0)"
    [ -z "$sid" ] && continue

    # Sanitize sid for the item name (alphanumeric + hyphens only).
    safe_sid="$(printf '%s' "$sid" | tr -c 'A-Za-z0-9-' '_')"
    item_name="claude.popup.${safe_sid}"

    if [ "$status" = "running" ]; then
      icon="●"
    else
      icon="○"
    fi

    sketchybar --add item "$item_name" popup.claude \
               --set "$item_name" \
                     label="${label} · ${status} · ${dur}s" \
                     icon="$icon" \
      2>/dev/null || true
    i=$((i + 1))
  done < <(jq -c '.sessions | to_entries[]' "$STATE_FILE" 2>/dev/null || echo '')
fi

sketchybar --set claude popup.drawing=toggle 2>/dev/null || true
exit 0
