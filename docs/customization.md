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

By default the project label shown in notifications and in the widget is
`basename($cwd)`. To customize, edit
`~/.claude/scripts/notifier/notify-stop.sh` and replace this line:

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

## Widget position

The widget lives at:

```
~/Library/Application Support/Übersicht/widgets/claude-sessions.widget/index.jsx
```

The first lines of `className` control its position. Defaults:

```css
position: absolute;
top: 36px;     /* clear of the macOS menu bar */
left: 20px;
width: 320px;
```

Übersicht hot-reloads the widget the moment you save the file — no restart
required. To pin the widget to the right side of the screen, replace `left`
with `right`. To hug a different corner, use `bottom` instead of `top`.

## Widget colors and icon

The same `index.jsx` carries the full visual definition. The four state
colors are inline in the CSS section:

```css
.icon.running { color: #ffd60a; }   /* a turn is running */
.icon.idle    { color: #34c759; }   /* sessions waiting   */
.icon.ended   { color: #8e8e93; }   /* only completed     */
.icon.empty   { color: #636366; }   /* nothing            */

.dot.running { background: #ffd60a; box-shadow: 0 0 6px rgba(255, 214, 10, 0.5); }
.dot.idle    { background: #34c759; }
.dot.ended   { background: rgba(142, 142, 147, 0.6); }
```

The icon glyph is the `◆` character in the header. Swap it for any glyph
from SF Symbols, Nerd Fonts, or plain Unicode (e.g. `⚡`, `🤖`, ``).

## Recently completed cap

The widget shows the most recent 8 ended sessions. Tweak the slice:

```jsx
const ended = sessions
  .filter((s) => s.status === 'ended')
  .sort((a, b) => (b.ended_at || '').localeCompare(a.ended_at || ''))
  .slice(0, 8);   // <-- raise or lower this
```

Pair this with `CLAUDE_ENDED_TTL` (default `3600`s) which controls how long
ended entries live in `active-sessions.json` before being purged.

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
of `~/.claude/settings.json`, or move them to a backup file. To hide just
the widget, click the Übersicht menu-bar icon and toggle `claude-sessions`
off.

## Notification backend

By default we use `terminal-notifier` (richer, supports `-group` to coalesce
notifications per session). If `terminal-notifier` fails or is missing,
`hooks/lib/notify.sh` falls back to `osascript "display notification"`.

To force the AppleScript path even when `terminal-notifier` is installed,
edit `notify.sh` and short-circuit `notify_user` to call `_notify_osascript`
directly.
