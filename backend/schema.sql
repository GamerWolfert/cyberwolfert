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
  created_at TIMESTAMPTZ DEFAULT NOW()
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

INSERT INTO users (username) VALUES ('wolfert') ON CONFLICT (username) DO NOTHING;
INSERT INTO user_settings (user_id, theme, background_type, background_value)
SELECT id, 'dark', 'color', '#0B1020' FROM users WHERE username='wolfert'
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO custom_links (user_id, keyword, title, url, description, priority)
SELECT id, 'wolfbos', 'Wolfbos Dashboard', 'http://192.168.1.42:43711/', 'Lokaal dashboard op Mini-PC', 1000
FROM users WHERE username='wolfert'
ON CONFLICT DO NOTHING;
