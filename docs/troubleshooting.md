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

## SketchyBar doesn't show up

1. Confirm the service is running:
   ```bash
   brew services list | grep sketchybar
   ```
   If it's not `started`, run `brew services start sketchybar`.
2. macOS may hide the menu bar in fullscreen apps. Open
   `System Settings > Control Center > Menu Bar Only > Automatically hide
   and show the menu bar` and set to `Never` (or `In Full Screen Only`,
   depending on preference).
3. If you're on macOS 14+ and using a notch display, SketchyBar items render
   to the right of the notch — make sure the `claude` item has
   `right` as its position (default in `sketchybarrc.example`).
4. Force a refresh:
   ```bash
   sketchybar --reload
   ```

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

The same applies to `terminal-notifier` and `sketchybar` if hooks log
"command not found".

## State file corrupted

The notifier auto-recovers: any unparseable
`~/.claude/active-sessions.json` is renamed to
`active-sessions.json.broken-<timestamp>` and replaced with an empty state.

To force a manual reset:

```bash
rm ~/.claude/active-sessions.json
sketchybar --trigger claude_done    # repaint the bar
```

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
