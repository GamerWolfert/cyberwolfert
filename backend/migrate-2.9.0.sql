-- Migratie naar 2.9.0 (idempotent): AeroTalk-gesprekken (bellen)
-- 1) ws_calls: log van oproepen (ook als niemand opneemt -> "gemist")
CREATE TABLE IF NOT EXISTS ws_calls (
  id SERIAL PRIMARY KEY,
  caller_id INT REFERENCES users(id) ON DELETE SET NULL,
  callee_id INT REFERENCES users(id) ON DELETE SET NULL,
  kind VARCHAR(16) NOT NULL DEFAULT 'video',
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  end_reason VARCHAR(32),
  duration_sec INT NOT NULL DEFAULT 0,
  read_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_ws_calls_callee ON ws_calls (callee_id, id DESC);
CREATE INDEX IF NOT EXISTS idx_ws_calls_pair ON ws_calls (LEAST(caller_id, callee_id), GREATEST(caller_id, callee_id), id DESC);
