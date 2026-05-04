# How it works

`claude-code-notifier` is a thin layer of bash scripts wired into Claude Code's
hook system, plus an Übersicht widget that renders the resulting state.

## Lifecycle map

Claude Code emits hook events at well-defined points. We subscribe to four:

```
+---------------------+      +-----------------------+      +---------------+      +------------------------+
| SessionStart        |  ->  | UserPromptSubmit      |  ->  | Stop          |  ->  | SessionEnd             |
| register-session.sh |      | mark-prompt-start.sh  |      | notify-stop.sh|      | unregister-session.sh  |
+---------------------+      +-----------------------+      +---------------+      +------------------------+
        |                              |                          |                            |
        v                              v                          v                            v
   upsert session              status=running, set       status=idle, compute            mark sessions[sid]
   in state file               prompt_started_at         duration, decide notify         status=ended
```

Each mutation rewrites `~/.claude/active-sessions.json` atomically. The
Übersicht widget polls that file every 5 seconds (`refreshFrequency`) and
re-renders the panel. There is no IPC between the bash layer and the UI —
the JSON file is the contract.

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
      "status": "running", /* or "idle" or "ended" */
      "ended_at": "2026-05-04T12:35:10Z",
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
active    = number of sessions in state file with status in {running, idle}

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
   transitions any whose process is gone (`kill -0 <pid>` fails) to
   `status: "ended"`.
2. `cleanup-sessions.sh` runs on a similar pass and is safe to invoke
   repeatedly. It honours `CLAUDE_ENDED_TTL` (default `3600`s) when purging
   long-dead `ended` entries.

## UI rendering path

```
hook event -> writes ~/.claude/active-sessions.json
                                |
                                v
            Übersicht polls every 5s (refreshFrequency)
                                |
                                v
            command: cat "$HOME/.claude/active-sessions.json"
                                |
                                v
            render(): partition into running / idle / ended,
                      paint glass panel with backdrop-filter blur
```

The widget is a single self-contained `index.jsx` (no bundler, no external
imports). It uses Übersicht's built-in JSX runtime and Emotion CSS-in-JS for
styling. The shell command runs each tick — there is no long-running watcher.

## Why bash + JSX

There are no daemons, no node, no python on the backend. The whole hook
pipeline is sourced bash that finishes in milliseconds. The frontend is a
single JSX file that runs inside Übersicht's WebKit host. The only runtime
dependencies are tools you already have or want anyway: `jq` for state,
`terminal-notifier` for native notifications, Übersicht for the widget.

## References

- Claude Code hooks reference:
  https://docs.claude.com/en/docs/claude-code/hooks
- Übersicht:
  https://tracesof.net/uebersicht/
- terminal-notifier:
  https://github.com/julienXX/terminal-notifier
