-- Migratie naar 2.4.2 (idempotent): online-aanwezigheid van gebruikers
-- (laatste activity-moment, gebruikt voor de groene "online"-stip bij vrienden).
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen TIMESTAMPTZ;
