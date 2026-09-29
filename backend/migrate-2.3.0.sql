-- Migratie naar 2.3.0 (idempotent): eigen e-maildomeinen, mailboxen en inbox.
-- Admin maakt mailboxen aan (naam@domein), geeft gebruikers toegang of draagt
-- het eigendom over. Inkomende mail komt binnen via de eigen SMTP-server of
-- via de webhook-relay; uitgaand gaat via de MAIL_*-relay (of intern direct).

CREATE TABLE IF NOT EXISTS mail_domains (
  id SERIAL PRIMARY KEY,
  domain VARCHAR(255) NOT NULL UNIQUE,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mail_mailboxes (
  id SERIAL PRIMARY KEY,
  localpart VARCHAR(64) NOT NULL,
  domain_id INT NOT NULL REFERENCES mail_domains(id) ON DELETE CASCADE,
  owner_user_id INT REFERENCES users(id) ON DELETE SET NULL,
  display_name VARCHAR(128),
  created_by INT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_mail_mailboxes_addr
  ON mail_mailboxes (domain_id, LOWER(localpart));

CREATE TABLE IF NOT EXISTS mail_access (
  id SERIAL PRIMARY KEY,
  mailbox_id INT NOT NULL REFERENCES mail_mailboxes(id) ON DELETE CASCADE,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(16) NOT NULL DEFAULT 'full',
  granted_by INT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (mailbox_id, user_id)
);

CREATE TABLE IF NOT EXISTS mail_messages (
  id SERIAL PRIMARY KEY,
  mailbox_id INT NOT NULL REFERENCES mail_mailboxes(id) ON DELETE CASCADE,
  dir VARCHAR(4) NOT NULL DEFAULT 'in',
  from_addr VARCHAR(255) NOT NULL,
  to_addr VARCHAR(255) NOT NULL,
  subject TEXT NOT NULL DEFAULT '',
  body_text TEXT NOT NULL DEFAULT '',
  body_html TEXT NOT NULL DEFAULT '',
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  code VARCHAR(32),
  external_id VARCHAR(160),
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_mail_messages_box
  ON mail_messages (mailbox_id, received_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_mail_messages_ext
  ON mail_messages (external_id) WHERE external_id IS NOT NULL;

-- Standaarddomein (admin kan later domeinen toevoegen/wijzigen).
INSERT INTO mail_domains (domain, is_default, active)
SELECT 'cyberwolfert.nl', true, true
WHERE NOT EXISTS (SELECT 1 FROM mail_domains);

UPDATE mail_domains SET is_default = true
 WHERE is_default = false
   AND id = (SELECT id FROM mail_domains ORDER BY id LIMIT 1)
   AND NOT EXISTS (SELECT 1 FROM mail_domains WHERE is_default);

-- Nieuwe permissie: mailboxen aanmaken, toegang geven, eigendom overdragen.
UPDATE site_roles SET permissions = permissions || '{"mail.manage": true}'::jsonb
 WHERE name = 'admin' AND NOT (permissions ? 'mail.manage');
