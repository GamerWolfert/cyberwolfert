-- Migratie naar 2.2.0 (idempotent): WolfSyn verdwijnende berichten + AI-agent
-- Berichten verdwijnen 20 seconden nadat iedereen ze gelezen heeft.
ALTER TABLE ws_messages ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
ALTER TABLE ws_dms ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS ws_message_reads (
  message_id INT REFERENCES ws_messages(id) ON DELETE CASCADE,
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  read_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_ws_message_reads_msg ON ws_message_reads(message_id);

CREATE TABLE IF NOT EXISTS ws_message_log (
  id SERIAL PRIMARY KEY,
  kind VARCHAR(16) NOT NULL,
  ref_id INT,
  message_id INT,
  user_id INT,
  username VARCHAR(64),
  body TEXT,
  reason VARCHAR(24),
  deleted_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ws_message_log_time ON ws_message_log(deleted_at DESC);

-- Nieuwe permissie voor de AI-agent (admin-rol meenemen).
UPDATE site_roles SET permissions = permissions || '{"agent.run": true}'::jsonb
 WHERE name = 'admin' AND NOT (permissions ? 'agent.run');
