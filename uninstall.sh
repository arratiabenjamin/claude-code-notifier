#!/usr/bin/env bash
# claude-code-notifier uninstaller.
# Idempotent. Removes hooks, scripts, and the Übersicht widget installed by install.sh.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { printf "${BLUE}==>${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}✓${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}!${NC}  %s\n" "$*"; }
fail()  { printf "${RED}✗${NC}  %s\n" "$*" >&2; }

NOTIFIER_DIR="${HOME}/.claude/scripts/notifier"
WIDGET_DIR="${HOME}/Library/Application Support/Übersicht/widgets/claude-sessions.widget"
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

# ---------- 3. Remove Übersicht widget ----------
if [ -d "${WIDGET_DIR}" ]; then
  info "Removing Übersicht widget at ${WIDGET_DIR}"
  rm -rf "${WIDGET_DIR}"
  ok "Widget removed"
else
  ok "No widget directory, skipping"
fi

# ---------- 4. Optionally drop state file ----------
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

# ---------- 5. Final notes ----------
echo
ok "Uninstall complete."
echo
cat <<EOF
You may want to:
  - Refresh Übersicht so the widget disappears: open the menu-bar icon and
    pick "Refresh All Widgets" (or relaunch the app).
  - Remove the disable flag (if set): rm -f ~/.claude/notifier-disabled
  - Fully uninstall Übersicht (optional, only if you don't use it for other
    widgets):
      brew uninstall --cask ubersicht
EOF
