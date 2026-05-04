# Customization

## Notification threshold

Notifications fire when a turn takes longer than `THRESHOLD_SECONDS`
(default: `90`) OR there are multiple active sessions.

Override via environment variable:

```bash
# In your ~/.zshrc or ~/.bashrc
export CLAUDE_NOTIFY_THRESHOLD=120   # only fire after 2 minutes
```

Restart your terminal so Claude Code's hooks inherit the new value.

## Project labels

By default the project label shown in notifications and the SketchyBar popup
is `basename($cwd)`. To customize, edit `~/.claude/scripts/notifier/notify-stop.sh`
and replace this line:

```bash
project_label="$(basename "${cwd:-Claude}")"
```

Two patterns work well:

**Inline mapping:**

```bash
case "$cwd" in
  *"01.- Velion/Proyectos/Workly"*) project_label="Workly" ;;
  *"01.- Velion/Proyectos/Trakly"*) project_label="Trakly" ;;
  *) project_label="$(basename "${cwd:-Claude}")" ;;
esac
```

**External mapping file** (`~/.claude/notifier-labels.tsv`, two columns):

```bash
labels_file="${HOME}/.claude/notifier-labels.tsv"
project_label=""
if [ -f "$labels_file" ]; then
  while IFS=$'\t' read -r pattern label; do
    case "$cwd" in *"$pattern"*) project_label="$label"; break ;; esac
  done < "$labels_file"
fi
[ -z "$project_label" ] && project_label="$(basename "${cwd:-Claude}")"
```

## SketchyBar colors and icon

`~/.config/sketchybar/plugins/claude.sh` defines three hex colors:

```bash
color_grey="0xff666666"   # no active sessions
color_green="0xff44cc44"  # at least one idle session
color_yellow="0xffeebb22" # at least one running
```

Format is `0xAARRGGBB` (alpha first).

The icon is set in `sketchybarrc` (`icon="◆"`). Swap it for any glyph from
SF Symbols, Nerd Fonts, or plain Unicode (e.g. `"⚡"`, `"🤖"`, `""`).

## Pause notifications

```bash
# Pause (silences hooks but keeps state up to date)
touch ~/.claude/notifier-disabled

# Resume
rm ~/.claude/notifier-disabled
```

The flag is checked at the start of every hook except `unregister-session.sh`
(which still cleans up state when sessions end).

## Permanent disable

To remove everything, run `./uninstall.sh` from the repo. To temporarily
detach without deleting: comment out the entries inside the `hooks` block
of `~/.claude/settings.json`, or move them to a backup file.

## Notification backend

By default we use `terminal-notifier` (richer, supports `-group` to coalesce
notifications per session). If `terminal-notifier` fails or is missing,
`hooks/lib/notify.sh` falls back to `osascript "display notification"`.

To force the AppleScript path even when `terminal-notifier` is installed,
edit `notify.sh` and short-circuit `notify_user` to call `_notify_osascript`
directly.
