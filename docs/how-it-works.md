# How it works

`claude-code-notifier` is a thin layer of bash scripts wired into Claude Code's
hook system, plus a SketchyBar item that renders the resulting state.

## Lifecycle map

Claude Code emits hook events at well-defined points. We subscribe to four:

```
+---------------------+      +-----------------------+      +---------------+      +------------------------+
| SessionStart        |  ->  | UserPromptSubmit      |  ->  | Stop          |  ->  | SessionEnd             |
| register-session.sh |      | mark-prompt-start.sh  |      | notify-stop.sh|      | unregister-session.sh  |
+---------------------+      +-----------------------+      +---------------+      +------------------------+
        |                              |                          |                            |
        v                              v                          v                            v
   upsert session              status=running, set       status=idle, compute            del sessions[sid]
   in state file               prompt_started_at         duration, decide notify
```

After every mutation we trigger SketchyBar via `--trigger claude_done`, which
fires `claude.sh` to refresh the menu bar item.

## State file schema

Path: `~/.claude/active-sessions.json`

```jsonc
{
  "version": 1,
  "updated_at": "2026-05-04T12:34:56Z",
  "sessions": {
    "<session_id>": {
      "session_id": "<uuid>",
      "pid": 12345,
      "cwd": "/Users/you/code/awesome-app",
      "project_label": "awesome-app",
      "started_at": "2026-05-04T12:30:00Z",
      "prompt_started_at": "2026-05-04T12:34:00Z",
      "status": "running" /* or "idle" */,
      "last_turn_duration_s": 137,
      "last_turn_finished_at": "2026-05-04T12:34:56Z",
      "last_result": "ok",
      "transcript_path": "<optional>"
    }
  }
}
```

The schema is intentionally loose: any field can be missing on older sessions,
and the JSON is rewritten in full on each mutation, so partial entries
self-heal on the next event.

## Concurrency model

Multiple Claude Code processes can fire hooks simultaneously. To prevent
torn writes we use a single-writer lock backed by `mkdir`:

- `mkdir ~/.claude/active-sessions.lock` is atomic on macOS.
- Acquire wait: 50 retries × 100ms = 5 seconds max.
- Released via `trap` on `EXIT INT TERM` AND a final `rmdir` after the work.
- We deliberately avoid `flock(1)` because it isn't on macOS by default.

All writes go through `jq_mutate`:

1. Read current JSON.
2. Pipe through a `jq` filter (atomic transformation).
3. Write to a sibling temp file in the same directory.
4. `mv` over the original (atomic on the same filesystem).

If `jq` rejects the existing file (corruption), `ensure_state_file` moves the
broken file aside as `active-sessions.json.broken-<timestamp>` and starts
fresh — no data loss except the broken file's contents, which are preserved
for inspection.

## Notification decision tree

`notify-stop.sh` runs after every Stop event:

```
duration  = now - prompt_started_at  (0 if missing)
active    = number of sessions in state file after this turn closed

if duration > THRESHOLD_SECONDS:
    notify(project_label, duration, active)
elif active > 1:
    notify(project_label, duration, active)
else:
    skip
```

`THRESHOLD_SECONDS` defaults to `90` and is overridable via the
`CLAUDE_NOTIFY_THRESHOLD` environment variable (read at hook time).

## Self-cleaning sessions

Sessions can leak if Claude Code is killed by `SIGKILL` (no `SessionEnd`).
Two mechanisms catch this:

1. `notify-stop.sh` re-checks every PID after closing the current turn and
   removes any whose process is gone (`kill -0 <pid>` fails).
2. `cleanup-sessions.sh` is invoked by `claude.sh` (the SketchyBar plugin
   refresh script) before reading. So even an idle bar self-heals.

## SketchyBar refresh path

```
hook event -> sketchybar --trigger claude_done -> claude.sh
                                                  |
                                                  v
                                       cleanup-sessions.sh
                                                  |
                                                  v
                                read sessions, paint:
                                  running > 0  -> yellow
                                  count   > 0  -> green
                                  else         -> grey
```

The popup is rebuilt on every click via `claude_popup.sh`, which queries the
existing popup items, removes them, then iterates the state file and creates
one item per session.

## Why bash

There are no daemons, no node, no python. The whole pipeline is sourced bash
that finishes in milliseconds. The only runtime dependencies are tools you
already have or want anyway: `jq` for state, `terminal-notifier` for native
notifications, `sketchybar` for the menu bar item.

## References

- Claude Code hooks reference:
  https://docs.claude.com/en/docs/claude-code/hooks
- SketchyBar:
  https://github.com/FelixKratz/SketchyBar
- terminal-notifier:
  https://github.com/julienXX/terminal-notifier
