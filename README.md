# claude-code-notifier

> Ambient notifications + menu bar dashboard for Claude Code sessions on macOS.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-blue)](#requirements)
[![Made with Bash](https://img.shields.io/badge/made%20with-bash-1f425f.svg)](#)

<!-- ![demo](docs/demo.gif) -->

When you run multiple Claude Code sessions in parallel — across different
projects, different terminal windows — you lose track of which one is busy
and which one is idle. You either babysit them or come back five minutes
later wondering which task finished. This tool fixes that with two pieces:

- **macOS notifications** when a Claude Code task finishes (configurable threshold, per-project label).
- **A SketchyBar item** that always shows your active session count, with a popup listing each session.

## Why?

The pain is specific: parallel work breeds context-switching cost. Every
trip back to a terminal "to check" is a 30-second tax. Multiplied across
a day, that tax dwarfs the thing you were trying to speed up by running
sessions in parallel in the first place.

The fix is to push state to where your eyes already are — the menu bar — and
to interrupt only when it matters. The notifier hooks into Claude Code's
[official lifecycle events](https://docs.claude.com/en/docs/claude-code/hooks)
(`SessionStart`, `UserPromptSubmit`, `Stop`, `SessionEnd`), maintains a
small JSON state file, and renders that state in SketchyBar. Long tasks
fire a notification. Short tasks in a single session stay quiet. Everything
is plain bash.

## Features

- **Smart notifications** — fire only when it matters (turns longer than 90s OR multiple sessions active).
- **Per-project labels** — the notification tells you which project finished, not a generic "Claude Code".
- **Live menu bar dashboard** — SketchyBar item with a session counter and color-coded status (grey / green / yellow).
- **Pause anytime** — `touch ~/.claude/notifier-disabled` to silence; `rm` to resume.
- **Self-cleaning** — orphan sessions (killed with `SIGKILL`) are detected and removed from state.
- **Pure shell** — no daemons, no Electron, no Node — just bash hooks plus `jq`.
- **Atomic state** — `mkdir`-based locking and `mktemp + mv` swap; no `flock` dependency.

## Requirements

- macOS 13+ (developed and tested on macOS 15 / Sequoia and macOS 26 / Tahoe)
- [Claude Code CLI](https://docs.claude.com/en/docs/claude-code)
- [Homebrew](https://brew.sh)

The installer fetches the rest: `jq`, `terminal-notifier`, and `sketchybar`.

## Install

```bash
git clone https://github.com/arratiabenjamin/claude-code-notifier.git
cd claude-code-notifier
./install.sh
```

The installer will:

1. Install missing dependencies (`jq`, `terminal-notifier`, `sketchybar`) via Homebrew, prompting first.
2. Copy hook scripts to `~/.claude/scripts/notifier/`.
3. Copy SketchyBar plugins to `~/.config/sketchybar/plugins/`.
4. Register hooks in `~/.claude/settings.json`, preserving everything else in the file.
5. Start (or restart) `sketchybar` as a Homebrew service.

### One-time macOS permission

The first time `terminal-notifier` fires, macOS will prompt you to allow
notifications. Approve it, or open
`System Settings > Notifications > terminal-notifier` and turn on
**Allow Notifications**. Without this, hooks run fine but you'll see
nothing on screen.

## Configuration

| Knob | Where | Default |
|------|-------|---------|
| Notification threshold (seconds) | `CLAUDE_NOTIFY_THRESHOLD` env var | `90` |
| Pause notifications | create `~/.claude/notifier-disabled` | enabled |
| Project label | `basename($cwd)` in `notify-stop.sh` | folder name |
| SketchyBar colors | `~/.config/sketchybar/plugins/claude.sh` | grey/green/yellow |
| State file | `~/.claude/active-sessions.json` | auto-created |
| Log file | `~/.claude/scripts/notifier/notifier.log` | rotated at 1MB |

For deeper changes (custom project mapping, alternate notification backend,
SketchyBar styling) see [`docs/customization.md`](docs/customization.md).

## How it works

```
+---------------------+      +-----------------------+      +----------------+      +------------------------+
| SessionStart        |  ->  | UserPromptSubmit      |  ->  | Stop           |  ->  | SessionEnd             |
| register-session.sh |      | mark-prompt-start.sh  |      | notify-stop.sh |      | unregister-session.sh  |
+---------------------+      +-----------------------+      +----------------+      +------------------------+
        \____________________________________  __________________/
                                             \/
                              writes ~/.claude/active-sessions.json
                              triggers `sketchybar --trigger claude_done`
```

Every hook is short, side-effect-tolerant, and never crashes the parent
session — Claude Code keeps working even if `jq` is missing. The full
architecture (state schema, locking model, notification decision tree) is
in [`docs/how-it-works.md`](docs/how-it-works.md).

## Customization

Most users only touch two things: the threshold and the project labels.
Both take five minutes. See [`docs/customization.md`](docs/customization.md)
for the full menu — including how to swap the notification backend, recolor
the SketchyBar item, or define custom labels via an external mapping file.

## Troubleshooting

If notifications don't appear, SketchyBar won't show, or hooks seem to be
ignored, the answer is almost always in
[`docs/troubleshooting.md`](docs/troubleshooting.md). Common culprits:
Focus mode, `PATH` differences inside hooks, and the macOS notification
permission prompt that's easy to miss the first time.

Logs live at `~/.claude/scripts/notifier/notifier.log` — `tail -f` it while
reproducing the issue.

## Contributing

Pull requests welcome. Please run `shellcheck` on any script you touch:

```bash
shellcheck hooks/**/*.sh sketchybar/plugins/*.sh install.sh uninstall.sh
```

CI runs the same check on every PR.

## License

MIT — see [LICENSE](LICENSE).

## Made by

Built by [Benjamín Arratia](https://github.com/arratiabenjamin) at
[Velion](#) — a one-person software studio building a portfolio of products
that solve real, concrete problems for people and small businesses, instead
of selling client hours.

If this saved you time, a star on the repo is the easiest way to say thanks.
