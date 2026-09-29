-- Migratie naar 2.4.0 (idempotent): WolfSyn als Discord — server-tags,
-- vrienden, groeps-DM's en (gratis) server-boosts.

-- Server-tag: kiezen bij joinen, verschijnt achter je naam in die server.
ALTER TABLE ws_members ADD COLUMN IF NOT EXISTS server_tag VARCHAR(24);

-- Vrienden
CREATE TABLE IF NOT EXISTS ws_friend_requests (
  id SERIAL PRIMARY KEY,
  from_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (from_id, to_id)
);
CREATE INDEX IF NOT EXISTS idx_ws_friend_requests_to ON ws_friend_requests (to_id, status);

CREATE TABLE IF NOT EXISTS ws_friends (
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  since TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, friend_id)
);

-- Groeps-DM's (groepen met vrienden)
CREATE TABLE IF NOT EXISTS ws_groups (
  id SERIAL PRIMARY KEY,
  name VARCHAR(64) NOT NULL,
  owner_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS ws_group_members (
  group_id INT NOT NULL REFERENCES ws_groups(id) ON DELETE CASCADE,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (group_id, user_id)
);
CREATE TABLE IF NOT EXISTS ws_group_messages (
  id SERIAL PRIMARY KEY,
  group_id INT NOT NULL REFERENCES ws_groups(id) ON DELETE CASCADE,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ws_group_messages ON ws_group_messages (group_id, id);
CREATE TABLE IF NOT EXISTS ws_group_reads (
  message_id INT NOT NULL REFERENCES ws_group_messages(id) ON DELETE CASCADE,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id)
);

-- Server-boosts: gratis, geven alleen visuals (badge, kleur, niveau).
CREATE TABLE IF NOT EXISTS ws_boosts (
  server_id INT NOT NULL REFERENCES ws_servers(id) ON DELETE CASCADE,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (server_id, user_id)
);
ALTER TABLE ws_servers ADD COLUMN IF NOT EXISTS banner_color VARCHAR(16) DEFAULT '#29B6F6';
