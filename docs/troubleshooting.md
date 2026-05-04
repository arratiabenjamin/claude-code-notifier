# Troubleshooting

## Notifications don't appear visually

1. Check Focus mode (Do Not Disturb). If on, macOS swallows notifications.
2. Open `System Settings > Notifications > terminal-notifier` and confirm
   `Allow Notifications` is on. If `terminal-notifier` is not listed,
   trigger one notification first (e.g. let a long task finish) and macOS
   will surface the entry.
3. Verify `terminal-notifier` works on its own:
   ```bash
   terminal-notifier -title "Test" -message "It works"
   ```
4. As a last resort, force the AppleScript fallback path (see
   `docs/customization.md > Notification backend`).

## The widget doesn't appear

1. Confirm Übersicht is running. Look for the eye icon in the menu bar. If
   it's missing, launch the app:
   ```bash
   open -a "Übersicht"
   ```
2. Click the menu-bar icon and confirm `claude-sessions` is checked under
   "Widgets". If you don't see it in the list, pick "Open Widgets Folder"
   and verify that `claude-sessions.widget/index.jsx` is present.
3. Übersicht renders behind every app. If your desktop is hidden, the widget
   is hidden too. Use `Mission Control` or `cmd-F3` (Show Desktop) to peek.
4. The first time you launch Übersicht, macOS may ask for Accessibility
   and/or Screen Recording permissions. Approve them in
   `System Settings > Privacy & Security` so the widget can render and
   refresh smoothly.
5. To force a reload after editing the widget: click the Übersicht
   menu-bar icon and choose `Refresh All Widgets`.

## The widget appears but shows no data

1. Verify the state file exists:
   ```bash
   ls -l ~/.claude/active-sessions.json
   ```
   If it's missing, you haven't run a Claude Code session yet, or the hooks
   aren't registered. Check `~/.claude/settings.json`.
2. Open the Übersicht menu-bar icon and pick `Show Console`. Any JSON parse
   error or shell-command failure will appear there.
3. Sanity-check the file is valid JSON:
   ```bash
   jq . ~/.claude/active-sessions.json
   ```
   If `jq` errors, see "State file corrupted" below.

## "command not found: jq" inside hooks

Claude Code launches hooks with a minimal shell environment that may not
include the Homebrew prefix in `PATH`. Two fixes:

**Easiest:** symlink jq into a dir already on the default PATH:

```bash
sudo ln -sf "$(command -v jq)" /usr/local/bin/jq
```

**Cleaner:** export `PATH` at the top of `~/.claude/scripts/notifier/config.sh`:

```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
```

The same applies to `terminal-notifier` if hooks log "command not found".

## State file corrupted

The notifier auto-recovers: any unparseable
`~/.claude/active-sessions.json` is renamed to
`active-sessions.json.broken-<timestamp>` and replaced with an empty state.

To force a manual reset:

```bash
rm ~/.claude/active-sessions.json
```

The widget will repaint on its next refresh tick (default 5s).

## Notifications fire too often

- Raise the threshold:
  ```bash
  export CLAUDE_NOTIFY_THRESHOLD=180  # 3 minutes
  ```
- Or pause entirely with `touch ~/.claude/notifier-disabled`.
- Note: when 2+ sessions are open, the second-session rule fires regardless
  of duration. That's intentional: parallel work is exactly when you need
  the heads-up. To disable that rule, comment out the `if [ "$active" -gt 1 ]`
  block in `~/.claude/scripts/notifier/notify-stop.sh`.

## Hooks don't run at all

1. Confirm they're registered: `jq '.hooks' ~/.claude/settings.json`
2. Confirm the scripts are executable:
   ```bash
   ls -l ~/.claude/scripts/notifier/*.sh
   ```
3. Tail the log while you trigger an event:
   ```bash
   tail -f ~/.claude/scripts/notifier/notifier.log
   ```
4. If the log shows nothing after a Stop event, Claude Code never invoked
   the hook. Check that the path in `settings.json` matches an actual file
   on disk and that you restarted Claude Code after editing settings.

## Lock acquisition warnings

A line like `WARN: could not acquire lock after 5s` in the log usually means
a previous hook crashed before releasing the lock. Manual recovery:

```bash
rmdir ~/.claude/active-sessions.lock
```

If the warning recurs, file an issue with the surrounding log lines.
