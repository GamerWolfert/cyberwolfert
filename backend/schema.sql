-- =============================================
-- CyberWolfert DB schema (PostgreSQL op Mini-PC)
-- psql -h 192.168.1.42 -U wolfert -d cyberwolfert_db -f schema.sql
-- =============================================

CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(64) UNIQUE NOT NULL DEFAULT 'wolfert',
  password_hash TEXT,
  google_id TEXT UNIQUE,
  display_name VARCHAR(128),
  avatar_url TEXT,
  email VARCHAR(256),
  email_verified BOOLEAN DEFAULT FALSE,
  email_token TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(LOWER(email)) WHERE email IS NOT NULL;

-- Apparaten per gebruiker: onthouden-login, verbannen/deblokkeren via e-mail
CREATE TABLE IF NOT EXISTS devices (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  device_id VARCHAR(128) NOT NULL,
  label VARCHAR(128) DEFAULT 'Onbekend apparaat',
  banned BOOLEAN DEFAULT FALSE,
  last_seen TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, device_id)
);

-- Sessies ongeldig maken bij "dit was ik niet" (token blacklist op uitgegeven-voor)
CREATE TABLE IF NOT EXISTS revoked_tokens (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  revoked_before TIMESTAMPTZ DEFAULT NOW()
);

-- WolfSyn: servers (groepen), rollen, kanalen, berichten, DM's
CREATE TABLE IF NOT EXISTS ws_servers (
  id SERIAL PRIMARY KEY,
  owner_id INT REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(64) NOT NULL,
  invite_code VARCHAR(16) UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS ws_roles (
  id SERIAL PRIMARY KEY,
  server_id INT REFERENCES ws_servers(id) ON DELETE CASCADE,
  name VARCHAR(32) NOT NULL,
  color VARCHAR(16) DEFAULT '#29B6F6',
  can_manage BOOLEAN DEFAULT FALSE,
  can_kick BOOLEAN DEFAULT FALSE,
  position INT DEFAULT 0
);
CREATE TABLE IF NOT EXISTS ws_members (
  server_id INT REFERENCES ws_servers(id) ON DELETE CASCADE,
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  nick VARCHAR(64),
  PRIMARY KEY (server_id, user_id)
);
CREATE TABLE IF NOT EXISTS ws_member_roles (
  server_id INT NOT NULL,
  user_id INT NOT NULL,
  role_id INT REFERENCES ws_roles(id) ON DELETE CASCADE,
  PRIMARY KEY (server_id, user_id, role_id)
);
CREATE TABLE IF NOT EXISTS ws_channels (
  id SERIAL PRIMARY KEY,
  server_id INT REFERENCES ws_servers(id) ON DELETE CASCADE,
  name VARCHAR(48) NOT NULL,
  kind VARCHAR(16) DEFAULT 'text',
  position INT DEFAULT 0
);
CREATE TABLE IF NOT EXISTS ws_messages (
  id SERIAL PRIMARY KEY,
  channel_id INT REFERENCES ws_channels(id) ON DELETE CASCADE,
  user_id INT REFERENCES users(id) ON DELETE SET NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ws_messages_channel ON ws_messages(channel_id, id DESC);
CREATE TABLE IF NOT EXISTS ws_dms (
  id SERIAL PRIMARY KEY,
  from_id INT REFERENCES users(id) ON DELETE CASCADE,
  to_id INT REFERENCES users(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ws_dms_pair ON ws_dms(from_id, to_id, id DESC);

-- WolfSyn-profiel los van browser-loginnaam
CREATE TABLE IF NOT EXISTS ws_profiles (
  user_id INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  display_name VARCHAR(64),
  avatar_url TEXT,
  bio VARCHAR(256) DEFAULT '',
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_settings (
  user_id INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  theme VARCHAR(32) DEFAULT 'dark',
  background_type VARCHAR(32) DEFAULT 'color',
  background_value TEXT DEFAULT '#0B1020',
  accent_color VARCHAR(16) DEFAULT '#E63946',
  homepage_url TEXT DEFAULT 'wolfpulse://home',
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS backgrounds (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(128) NOT NULL,
  type VARCHAR(32) NOT NULL,
  value TEXT NOT NULL,
  is_active BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS search_history (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  query TEXT NOT NULL,
  source VARCHAR(32) DEFAULT 'wolfpulse',
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_search_history_user_time ON search_history(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS custom_links (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  keyword VARCHAR(128) NOT NULL,
  title VARCHAR(256) NOT NULL,
  url TEXT NOT NULL,
  description TEXT,
  priority INT DEFAULT 100,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_custom_links_keyword ON custom_links(keyword);

CREATE TABLE IF NOT EXISTS ai_chats (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(16) NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_memory (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  feit TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ai_memory_user ON ai_memory(user_id);

-- 8. Site-rollen met permissies (admin-paneel)
CREATE TABLE IF NOT EXISTS site_roles (
  name VARCHAR(48) PRIMARY KEY,
  permissions JSONB NOT NULL DEFAULT '{}'
);
CREATE TABLE IF NOT EXISTS site_user_roles (
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  role_name VARCHAR(48) REFERENCES site_roles(name) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_name)
);
CREATE TABLE IF NOT EXISTS site_user_perms (
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  perm VARCHAR(64) NOT NULL,
  allow BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (user_id, perm)
);
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT FALSE;

-- 9. Login/register-gebeurtenissen (live logs)
CREATE TABLE IF NOT EXISTS auth_events (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id) ON DELETE SET NULL,
  username VARCHAR(64),
  kind VARCHAR(32) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_auth_events_time ON auth_events(created_at DESC);

-- 10. Site-instellingen (mededeling op startpagina)
CREATE TABLE IF NOT EXISTS site_settings (
  key VARCHAR(64) PRIMARY KEY,
  value TEXT DEFAULT ''
);
INSERT INTO site_settings (key, value) VALUES ('announcement', '')
ON CONFLICT (key) DO NOTHING;
INSERT INTO site_roles (name, permissions) VALUES ('user', '{}')
ON CONFLICT (name) DO NOTHING;

INSERT INTO users (username) VALUES ('wolfert') ON CONFLICT (username) DO NOTHING;
INSERT INTO user_settings (user_id, theme, background_type, background_value)
SELECT id, 'dark', 'color', '#0B1020' FROM users WHERE username='wolfert'
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO custom_links (user_id, keyword, title, url, description, priority)
SELECT id, 'wolfbos', 'Wolfbos Dashboard', 'http://192.168.1.42:43711/', 'Lokaal dashboard op Mini-PC', 1000
FROM users WHERE username='wolfert'
ON CONFLICT DO NOTHING;
