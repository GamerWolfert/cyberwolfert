-- Migratie naar 2.1.0 (idempotent)
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT FALSE;

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
CREATE TABLE IF NOT EXISTS auth_events (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id) ON DELETE SET NULL,
  username VARCHAR(64),
  kind VARCHAR(32) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_auth_events_time ON auth_events(created_at DESC);
CREATE TABLE IF NOT EXISTS site_settings (
  key VARCHAR(64) PRIMARY KEY,
  value TEXT DEFAULT ''
);
INSERT INTO site_settings (key, value) VALUES ('announcement', '')
ON CONFLICT (key) DO NOTHING;
INSERT INTO site_roles (name, permissions) VALUES ('user', '{}')
ON CONFLICT (name) DO NOTHING;
INSERT INTO site_roles (name, permissions) VALUES
('moderator', '{"users.view": true, "logs.view": true, "logs.search": true, "logs.ai": true, "logs.logins": true, "wolf.servers": true}')
ON CONFLICT (name) DO UPDATE SET permissions=EXCLUDED.permissions;
INSERT INTO site_roles (name, permissions) VALUES
('admin', '{"users.view": true, "users.ban": true, "users.delete": true, "users.verify": true, "users.resetpw": true, "users.make_admin": true, "roles.view": true, "roles.create": true, "roles.edit": true, "roles.delete": true, "roles.assign": true, "perms.grant": true, "logs.view": true, "logs.search": true, "logs.ai": true, "logs.logins": true, "logs.system": true, "site.announce": true, "site.stats": true, "site.links": true, "site.maintenance": true, "wolf.servers": true, "ai.memory": true, "ai.engine": true, "mail.test": true}')
ON CONFLICT (name) DO UPDATE SET permissions=EXCLUDED.permissions;
