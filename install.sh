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
SBAR_SRC="${REPO_DIR}/sketchybar"

NOTIFIER_DIR="${HOME}/.claude/scripts/notifier"
SBAR_DIR="${HOME}/.config/sketchybar"
SBAR_PLUGINS_DIR="${SBAR_DIR}/plugins"
SETTINGS_FILE="${HOME}/.claude/settings.json"

# ---------- dependencies ----------
need_brew=()
have() { command -v "$1" >/dev/null 2>&1; }

info "Checking dependencies..."

if ! have brew; then
  fail "Homebrew is required. Install it from https://brew.sh and re-run."
  exit 1
fi
ok "Homebrew detected"

for tool in jq terminal-notifier sketchybar; do
  if have "$tool"; then
    ok "$tool already installed"
  else
    need_brew+=("$tool")
  fi
done

if [ "${#need_brew[@]}" -gt 0 ]; then
  warn "Missing: ${need_brew[*]}"
  printf "Install via Homebrew now? [Y/n] "
  read -r answer
  if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
    for pkg in "${need_brew[@]}"; do
      info "Installing $pkg..."
      if [ "$pkg" = "sketchybar" ]; then
        brew tap FelixKratz/formulae 2>/dev/null || true
      fi
      brew install "$pkg"
    done
  else
    fail "Aborting. Install missing dependencies and re-run."
    exit 1
  fi
fi

# Optional but recommended: SF Pro font fallback (sketchybar config uses it).
# We don't fail if the font isn't installed; users can swap it via customization.

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

# ---------- copy sketchybar plugins ----------
info "Installing SketchyBar plugins to ${SBAR_PLUGINS_DIR}"
mkdir -p "${SBAR_PLUGINS_DIR}"
cp "${SBAR_SRC}/plugins/claude.sh"       "${SBAR_PLUGINS_DIR}/claude.sh"
cp "${SBAR_SRC}/plugins/claude_popup.sh" "${SBAR_PLUGINS_DIR}/claude_popup.sh"
chmod +x "${SBAR_PLUGINS_DIR}/claude.sh" "${SBAR_PLUGINS_DIR}/claude_popup.sh"
ok "Plugins installed"

# Install or augment sketchybarrc.
if [ ! -f "${SBAR_DIR}/sketchybarrc" ]; then
  info "No existing sketchybarrc — installing the example config"
  cp "${SBAR_SRC}/sketchybarrc.example" "${SBAR_DIR}/sketchybarrc"
  chmod +x "${SBAR_DIR}/sketchybarrc"
  ok "sketchybarrc installed"
else
  warn "Existing sketchybarrc found at ${SBAR_DIR}/sketchybarrc"
  warn "Add the 'claude_done' event + 'claude' item from sketchybar/sketchybarrc.example manually."
fi

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

# ---------- start sketchybar ----------
info "Starting SketchyBar..."
if brew services list 2>/dev/null | grep -qE '^sketchybar\s+(started|running)'; then
  ok "SketchyBar already running"
  brew services restart sketchybar >/dev/null 2>&1 || true
  ok "SketchyBar restarted to pick up new config"
else
  brew services start sketchybar >/dev/null 2>&1 || warn "Could not start sketchybar via brew services"
  ok "SketchyBar started"
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

  2. Open a new Claude Code session. After the first prompt finishes, the
     SketchyBar item will turn green and show the session count. Long tasks
     (> 90s) or simultaneous sessions will trigger a macOS notification.

  3. Tweak the threshold by exporting CLAUDE_NOTIFY_THRESHOLD before launching
     Claude Code, e.g. in your shell rc:
       export CLAUDE_NOTIFY_THRESHOLD=120

  4. Pause notifications anytime:
       touch ~/.claude/notifier-disabled
     Re-enable:
       rm ~/.claude/notifier-disabled

  5. Logs live at ~/.claude/scripts/notifier/notifier.log

Enjoy!
EOF
