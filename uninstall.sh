#!/usr/bin/env bash
# claude-code-notifier uninstaller.
# Idempotent. Removes hooks, scripts, and SketchyBar items installed by install.sh.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { printf "${BLUE}==>${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}✓${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}!${NC}  %s\n" "$*"; }
fail()  { printf "${RED}✗${NC}  %s\n" "$*" >&2; }

NOTIFIER_DIR="${HOME}/.claude/scripts/notifier"
SBAR_PLUGINS_DIR="${HOME}/.config/sketchybar/plugins"
SETTINGS_FILE="${HOME}/.claude/settings.json"
STATE_FILE="${HOME}/.claude/active-sessions.json"

# ---------- 1. Remove hooks from settings.json ----------
if [ -f "${SETTINGS_FILE}" ]; then
  info "Removing notifier hooks from ${SETTINGS_FILE}"
  if command -v jq >/dev/null 2>&1; then
    tmp="$(mktemp)"
    # Strip every hook entry whose command path contains "notifier/", then
    # drop empty matchers and empty event arrays.
    if jq '
      def prune_event:
        (map(.hooks |= map(select(.command // "" | test("notifier/") | not))))
        | map(select((.hooks // []) | length > 0));
      .hooks |= (
        (. // {})
        | with_entries(.value |= prune_event)
        | with_entries(select((.value | length) > 0))
      )
      | (if (.hooks // {}) == {} then del(.hooks) else . end)
    ' "${SETTINGS_FILE}" > "${tmp}"; then
      mv "${tmp}" "${SETTINGS_FILE}"
      ok "Hooks removed (other settings preserved)"
    else
      rm -f "${tmp}"
      warn "Could not auto-edit ${SETTINGS_FILE}. Remove notifier entries manually."
    fi
  else
    warn "jq not found; cannot edit settings.json. Remove notifier entries manually."
  fi
else
  ok "No settings.json found, skipping"
fi

# ---------- 2. Remove notifier scripts ----------
if [ -d "${NOTIFIER_DIR}" ]; then
  info "Removing ${NOTIFIER_DIR}"
  rm -rf "${NOTIFIER_DIR}"
  ok "Removed notifier scripts"
else
  ok "No notifier directory, skipping"
fi

# ---------- 3. Remove SketchyBar items ----------
if command -v sketchybar >/dev/null 2>&1; then
  info "Removing SketchyBar items"
  # Find every item whose name starts with "claude" (claude + claude.popup.*)
  items="$(sketchybar --query bar 2>/dev/null \
    | jq -r '.items[]? | select(test("^claude(\\.|$)"))' 2>/dev/null || echo '')"
  if [ -n "$items" ]; then
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      sketchybar --remove "$item" >/dev/null 2>&1 || true
    done <<< "$items"
    ok "Removed SketchyBar items"
  else
    ok "No SketchyBar claude items to remove"
  fi
else
  warn "sketchybar binary not found; skipping live item removal"
fi

# ---------- 4. Remove SketchyBar plugin scripts ----------
for f in claude.sh claude_popup.sh; do
  if [ -f "${SBAR_PLUGINS_DIR}/${f}" ]; then
    rm -f "${SBAR_PLUGINS_DIR}/${f}"
    ok "Removed ${SBAR_PLUGINS_DIR}/${f}"
  fi
done

# ---------- 5. Optionally drop state file ----------
if [ -f "${STATE_FILE}" ]; then
  printf "Remove state file ${STATE_FILE} too? [y/N] "
  read -r answer
  if [[ "${answer:-N}" =~ ^[Yy]$ ]]; then
    rm -f "${STATE_FILE}"
    ok "State file removed"
  else
    warn "State file kept at ${STATE_FILE}"
  fi
fi

# ---------- 6. Final notes ----------
echo
ok "Uninstall complete."
echo
cat <<EOF
You may want to:
  - Restart SketchyBar to clean up: brew services restart sketchybar
  - If you used the example sketchybarrc and want to remove it:
      rm ~/.config/sketchybar/sketchybarrc
  - Remove the disable flag (if set): rm -f ~/.claude/notifier-disabled
EOF
