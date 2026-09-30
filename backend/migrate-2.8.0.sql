-- Migratie naar 2.8.0 (idempotent): AeroTalk Discord-pariteit
-- 1) Server-tag standaard ingesteld door de eigenaar (leden kunnen hem uitzetten)
-- 2) Kanaalcategorieen voor de kanaal-sidebar
-- 3) Server kan door de eigenaar verwijderd worden (cascade)
ALTER TABLE ws_servers ADD COLUMN IF NOT EXISTS tag VARCHAR(24);
ALTER TABLE ws_members ADD COLUMN IF NOT EXISTS tag_hidden BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE ws_channels ADD COLUMN IF NOT EXISTS category VARCHAR(48);
UPDATE ws_channels SET category = 'algemeen' WHERE category IS NULL OR category = '';
ALTER TABLE ws_channels ALTER COLUMN category SET DEFAULT 'algemeen';
