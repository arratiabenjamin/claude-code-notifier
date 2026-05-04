# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-05-04

### Changed
- **SketchyBar visual redesigned as a floating pill widget.** The bar is now
  fully transparent (`color=0x00000000`), so macOS's native menu bar is no
  longer covered by a grey strip. Only the rounded pill item is visible,
  hovering on the right side. Background `corner_radius=10`, generous
  padding, bold typography for the icon.
- **Item label now shows two counters: `active · ended`.** For example
  `2 · 5` means two live sessions and five recently completed ones.
- **Color now reflects four states**: grey (nothing), blue (only ended
  sessions visible), green (idle sessions present), amber (a turn is
  currently running).

### Added
- **Recently completed sessions are tracked**, not deleted. `SessionEnd`
  marks the entry as `status: "ended"` with an `ended_at` timestamp instead
  of dropping it from state. Same treatment for orphan sessions detected
  by the cleanup pass — they transition to `ended` rather than being
  removed silently.
- **`CLAUDE_ENDED_TTL` (default `3600`s)** controls how long ended
  sessions remain visible before being purged from state. Set to `0` to
  effectively disable the recent-history feature.
- **Popup now has two sections**: `ACTIVE` (running and idle) and
  `RECENTLY COMPLETED` (ended within TTL). Empty sections are hidden.
  Each ended entry shows the project label, last turn duration, and
  relative "Xm ago" timestamp.

### Fixed
- `notify-stop.sh` was counting `ended` sessions as active when computing
  the multi-session notification rule, which would have caused noisy
  notifications. Counting now filters by `status in {running, idle}`.

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
