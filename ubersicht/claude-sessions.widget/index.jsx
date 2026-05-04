// claude-sessions.widget — Übersicht widget for claude-code-notifier.
//
// Reads ~/.claude/active-sessions.json (maintained by the hooks layer) and
// renders a glass-effect floating panel listing active and recently completed
// Claude Code sessions. Self-contained: no external imports, no bundler.

export const refreshFrequency = 5000; // ms — re-read state every 5s

// Übersicht executes `command` via the shell each refresh tick.
// Quoting the path (with $HOME) covers users whose home directory has spaces.
export const command =
  "cat \"$HOME/.claude/active-sessions.json\" 2>/dev/null || echo '{\"sessions\":{}}'";

// CSS-in-JS via Emotion (Übersicht's built-in styling layer). Nested selectors
// work the same way as in SCSS — Emotion compiles them at runtime.
export const className = `
  position: absolute;
  top: 36px;
  left: 20px;
  width: 320px;
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', sans-serif;
  font-size: 13px;
  color: #fff;
  background: rgba(28, 28, 30, 0.62);
  backdrop-filter: blur(28px) saturate(180%);
  -webkit-backdrop-filter: blur(28px) saturate(180%);
  border-radius: 16px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  padding: 14px 16px;
  box-shadow:
    0 12px 32px rgba(0, 0, 0, 0.32),
    0 2px 6px rgba(0, 0, 0, 0.18);
  user-select: none;
  -webkit-user-select: none;

  .header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 10px;
  }
  .header-left {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .icon {
    font-size: 16px;
    line-height: 1;
    color: #fff;
  }
  .icon.running { color: #ffd60a; }
  .icon.idle    { color: #34c759; }
  .icon.ended   { color: #8e8e93; }
  .icon.empty   { color: #636366; }

  .title {
    font-weight: 600;
    font-size: 13px;
    letter-spacing: -0.01em;
  }

  .counters {
    font-variant-numeric: tabular-nums;
    font-size: 12px;
    color: rgba(255, 255, 255, 0.65);
    background: rgba(255, 255, 255, 0.06);
    padding: 3px 9px;
    border-radius: 999px;
    border: 1px solid rgba(255, 255, 255, 0.05);
  }

  .section-header {
    font-size: 9.5px;
    font-weight: 700;
    letter-spacing: 0.08em;
    color: rgba(255, 255, 255, 0.45);
    text-transform: uppercase;
    margin: 10px 0 4px;
    padding: 0 2px;
  }

  .row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 5px 4px;
    border-radius: 7px;
    transition: background 120ms ease;
  }
  .row + .row { border-top: 1px solid rgba(255, 255, 255, 0.04); }
  .row:hover  { background: rgba(255, 255, 255, 0.05); }

  .dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    flex: 0 0 auto;
  }
  .dot.running { background: #ffd60a; box-shadow: 0 0 6px rgba(255, 214, 10, 0.5); }
  .dot.idle    { background: #34c759; }
  .dot.ended   { background: rgba(142, 142, 147, 0.6); }

  .row-label {
    flex: 1 1 auto;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 12.5px;
    color: rgba(255, 255, 255, 0.92);
  }
  .row.ended .row-label { color: rgba(255, 255, 255, 0.55); }

  .row-meta {
    flex: 0 0 auto;
    font-size: 11px;
    color: rgba(255, 255, 255, 0.45);
    font-variant-numeric: tabular-nums;
  }

  .empty-state {
    font-size: 12px;
    color: rgba(255, 255, 255, 0.45);
    font-style: italic;
    padding: 4px 2px;
  }
`;

export const render = ({ output, error }) => {
  if (error) {
    return <div className="empty-state">Notifier: read error</div>;
  }

  let data;
  try {
    data = JSON.parse(output);
  } catch (e) {
    return <div className="empty-state">Notifier: parse error</div>;
  }

  const sessions = Object.entries(data.sessions || {}).map(([sid, s]) => ({
    sid,
    ...s,
  }));
  const running = sessions.filter((s) => s.status === 'running');
  const idle = sessions.filter((s) => s.status === 'idle');
  const ended = sessions
    .filter((s) => s.status === 'ended')
    .sort((a, b) => (b.ended_at || '').localeCompare(a.ended_at || ''))
    .slice(0, 8);

  const activeCount = running.length + idle.length;
  const endedCount = ended.length;

  let stateClass = 'empty';
  if (running.length > 0) stateClass = 'running';
  else if (activeCount > 0) stateClass = 'idle';
  else if (endedCount > 0) stateClass = 'ended';

  const fmtAgo = (ts) => {
    if (!ts) return '—';
    const then = new Date(ts).getTime();
    const now = Date.now();
    const diff = Math.max(0, Math.floor((now - then) / 1000));
    if (diff < 60) return `${diff}s`;
    if (diff < 3600) return `${Math.floor(diff / 60)}m`;
    return `${Math.floor(diff / 3600)}h`;
  };

  const renderRow = (s, statusForDot) => (
    <div className={`row ${s.status}`} key={s.sid}>
      <div className={`dot ${statusForDot}`} />
      <div className="row-label">{s.project_label || s.cwd || s.sid}</div>
      <div className="row-meta">
        {s.status === 'running' && '· running'}
        {s.status === 'idle' &&
          (s.last_turn_duration_s != null ? `· ${s.last_turn_duration_s}s` : '· idle')}
        {s.status === 'ended' &&
          (s.last_turn_duration_s != null ? `· ${s.last_turn_duration_s}s` : '')}
        {' · '}
        {fmtAgo(
          s.status === 'ended'
            ? s.ended_at
            : s.prompt_started_at || s.last_turn_finished_at || s.started_at
        )}
      </div>
    </div>
  );

  return (
    <div>
      <div className="header">
        <div className="header-left">
          <span className={`icon ${stateClass}`}>◆</span>
          <span className="title">Claude Code</span>
        </div>
        <span className="counters">
          {activeCount} · {endedCount}
        </span>
      </div>

      {activeCount > 0 && (
        <div>
          <div className="section-header">Active</div>
          {running.map((s) => renderRow(s, 'running'))}
          {idle.map((s) => renderRow(s, 'idle'))}
        </div>
      )}

      {endedCount > 0 && (
        <div>
          <div className="section-header">Recently completed</div>
          {ended.map((s) => renderRow(s, 'ended'))}
        </div>
      )}

      {activeCount === 0 && endedCount === 0 && (
        <div className="empty-state">No active sessions</div>
      )}
    </div>
  );
};
