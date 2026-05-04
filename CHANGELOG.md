# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-04

### Added
- Four Claude Code hooks (`SessionStart`, `UserPromptSubmit`, `Stop`,
  `SessionEnd`) that maintain an `~/.claude/active-sessions.json` state file
  with per-session status, project label, PID, and turn duration.
- macOS notifications via `terminal-notifier` with an `osascript` fallback.
  Notifications fire when a turn exceeds `CLAUDE_NOTIFY_THRESHOLD` seconds
  (default `90`) or when more than one Claude Code session is active.
- SketchyBar item with a session counter and color-coded status (grey =
  idle, green = idle session present, yellow = a turn is running). Click
  toggles a popup listing each active session with its project label,
  status, and last turn duration.
- Self-cleaning logic that removes orphan sessions whose PIDs no longer
  exist (covers `SIGKILL` exits without `SessionEnd`).
- Atomic state writes via `mkdir`-based locking and `mktemp + mv` swap; no
  `flock` dependency.
- Disable flag (`~/.claude/notifier-disabled`) for one-touch pause.
- One-shot `install.sh` and `uninstall.sh`. Installer is idempotent and
  merges hooks into an existing `~/.claude/settings.json` via `jq` without
  clobbering other settings.
- Documentation: how-it-works architecture deep dive, customization guide,
  troubleshooting playbook.
- GitHub Actions workflow running `shellcheck` on every push and pull
  request.
