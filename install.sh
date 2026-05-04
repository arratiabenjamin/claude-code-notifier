#!/usr/bin/env bash
# claude-code-notifier installer.
# Idempotent. Safe to re-run.

set -euo pipefail

# ---------- pretty output ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { printf "${BLUE}==>${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}✓${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}!${NC}  %s\n" "$*"; }
fail()  { printf "${RED}✗${NC}  %s\n" "$*" >&2; }

# ---------- pre-flight ----------
if [ "$(uname -s)" != "Darwin" ]; then
  fail "claude-code-notifier currently supports macOS only (detected: $(uname -s))."
  fail "If you'd like Linux support, contributions are welcome."
  exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_SRC="${REPO_DIR}/hooks"
WIDGET_SRC="${REPO_DIR}/ubersicht/claude-sessions.widget"

NOTIFIER_DIR="${HOME}/.claude/scripts/notifier"
WIDGETS_DIR="${HOME}/Library/Application Support/Übersicht/widgets"
WIDGET_DEST="${WIDGETS_DIR}/claude-sessions.widget"
SETTINGS_FILE="${HOME}/.claude/settings.json"

# ---------- dependencies ----------
need_brew_formulae=()
need_brew_casks=()
have() { command -v "$1" >/dev/null 2>&1; }

info "Checking dependencies..."

if ! have brew; then
  fail "Homebrew is required. Install it from https://brew.sh and re-run."
  exit 1
fi
ok "Homebrew detected"

# CLI tools (formulae)
for tool in jq terminal-notifier; do
  if have "$tool"; then
    ok "$tool already installed"
  else
    need_brew_formulae+=("$tool")
  fi
done

# Übersicht (cask). Detected by app bundle, not by a CLI binary.
if [ -d "/Applications/Übersicht.app" ] || [ -d "${HOME}/Applications/Übersicht.app" ]; then
  ok "Übersicht already installed"
else
  need_brew_casks+=("ubersicht")
fi

if [ "${#need_brew_formulae[@]}" -gt 0 ] || [ "${#need_brew_casks[@]}" -gt 0 ]; then
  warn "Missing: ${need_brew_formulae[*]:-} ${need_brew_casks[*]:-}"
  printf "Install via Homebrew now? [Y/n] "
  read -r answer
  if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
    for pkg in "${need_brew_formulae[@]}"; do
      info "Installing $pkg..."
      brew install "$pkg"
    done
    for cask in "${need_brew_casks[@]}"; do
      info "Installing $cask (cask)..."
      brew install --cask "$cask"
    done
  else
    fail "Aborting. Install missing dependencies and re-run."
    exit 1
  fi
fi

# ---------- copy hooks ----------
info "Installing hooks to ${NOTIFIER_DIR}"
mkdir -p "${NOTIFIER_DIR}/lib"

for f in config.sh register-session.sh mark-prompt-start.sh notify-stop.sh \
         unregister-session.sh cleanup-sessions.sh; do
  cp "${HOOKS_SRC}/${f}" "${NOTIFIER_DIR}/${f}"
  chmod +x "${NOTIFIER_DIR}/${f}"
done

for f in json-helpers.sh notify.sh; do
  cp "${HOOKS_SRC}/lib/${f}" "${NOTIFIER_DIR}/lib/${f}"
  chmod 0644 "${NOTIFIER_DIR}/lib/${f}"
done
ok "Hooks installed"

# ---------- copy Übersicht widget ----------
info "Installing Übersicht widget to ${WIDGET_DEST}"
mkdir -p "${WIDGETS_DIR}"
mkdir -p "${WIDGET_DEST}"
cp "${WIDGET_SRC}/index.jsx" "${WIDGET_DEST}/index.jsx"
chmod 0644 "${WIDGET_DEST}/index.jsx"
ok "Widget installed"

# ---------- merge hooks into settings.json ----------
info "Registering hooks in ${SETTINGS_FILE}"
mkdir -p "$(dirname "${SETTINGS_FILE}")"

# Build the desired hooks block. Use absolute paths under $HOME so Claude Code
# can resolve them regardless of how it was launched.
read -r -d '' HOOKS_BLOCK <<'JSON' || true
{
  "SessionStart": [
    {
      "matcher": "",
      "hooks": [
        { "type": "command", "command": "HOME_PLACEHOLDER/.claude/scripts/notifier/register-session.sh" }
      ]
    }
  ],
  "UserPromptSubmit": [
    {
      "matcher": "",
      "hooks": [
        { "type": "command", "command": "HOME_PLACEHOLDER/.claude/scripts/notifier/mark-prompt-start.sh" }
      ]
    }
  ],
  "Stop": [
    {
      "matcher": "",
      "hooks": [
        { "type": "command", "command": "HOME_PLACEHOLDER/.claude/scripts/notifier/notify-stop.sh" }
      ]
    }
  ],
  "SessionEnd": [
    {
      "matcher": "",
      "hooks": [
        { "type": "command", "command": "HOME_PLACEHOLDER/.claude/scripts/notifier/unregister-session.sh" }
      ]
    }
  ]
}
JSON

HOOKS_BLOCK="${HOOKS_BLOCK//HOME_PLACEHOLDER/${HOME}}"

if [ ! -f "${SETTINGS_FILE}" ]; then
  printf '{\n  "hooks": %s\n}\n' "${HOOKS_BLOCK}" > "${SETTINGS_FILE}"
  ok "Created ${SETTINGS_FILE} with hooks"
else
  # Detect if our hooks are already present (idempotency).
  if jq -e '.hooks.Stop[]?.hooks[]?.command // "" | test("notifier/notify-stop.sh")' \
        "${SETTINGS_FILE}" >/dev/null 2>&1; then
    ok "Hooks already registered (skipping)"
  else
    tmp="$(mktemp)"
    if jq --argjson hooks "${HOOKS_BLOCK}" '.hooks = ((.hooks // {}) * $hooks)' \
        "${SETTINGS_FILE}" > "${tmp}"; then
      mv "${tmp}" "${SETTINGS_FILE}"
      ok "Merged hooks into existing settings.json"
    else
      rm -f "${tmp}"
      fail "Failed to merge hooks into ${SETTINGS_FILE}"
      fail "Inspect the file manually and copy the block from settings.example.json."
      exit 1
    fi
  fi
fi

# ---------- start Übersicht ----------
info "Launching Übersicht..."
if open -a "Übersicht" 2>/dev/null; then
  ok "Übersicht launched (or already running)"
else
  warn "Could not launch Übersicht via 'open -a'. Start it manually from /Applications."
fi

# ---------- final notes ----------
echo
ok "Installation complete."
echo
cat <<EOF
Next steps:

  1. The first time terminal-notifier fires, macOS will ask you to allow
     notifications. Approve it, or open:
       System Settings > Notifications > terminal-notifier
     and set Allow Notifications = on.

  2. Übersicht runs as a menu-bar app (look for the eye icon). Click it and
     make sure 'claude-sessions' is enabled under "Widgets". The panel
     appears at top:36px / left:20px by default — tweak these values in
     ${WIDGET_DEST}/index.jsx if you want a different position.
     Übersicht hot-reloads the widget on file save.

  3. Open a new Claude Code session. The widget reads
     ~/.claude/active-sessions.json every 5s and updates the panel. Long
     turns (> 90s) and concurrent sessions also fire a macOS notification.

  4. Tweak the threshold by exporting CLAUDE_NOTIFY_THRESHOLD before launching
     Claude Code, e.g. in your shell rc:
       export CLAUDE_NOTIFY_THRESHOLD=120

  5. Pause notifications anytime:
       touch ~/.claude/notifier-disabled
     Re-enable:
       rm ~/.claude/notifier-disabled

  6. Logs live at ~/.claude/scripts/notifier/notifier.log

Enjoy!
EOF
