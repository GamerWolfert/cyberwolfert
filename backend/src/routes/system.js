// Systeem-routes: versie/update-check + downloads + universele log-API.
const express = require('express');
const path = require('path');
const fs = require('fs');
const db = require('../db');
const { send, CHANNELS } = require('../discord');
const router = express.Router();

function loadVersion() {
  try {
    return JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'version.json'), 'utf8'));
  } catch {
    return { app: 'AeroSurf Browser', version: '0.0.0', build: 0 };
  }
}

function downloadDir() {
  const d = path.join(__dirname, '..', '..', 'downloads');
  fs.mkdirSync(d, { recursive: true });
  return d;
}

function publicBase(req) {
  if (process.env.PUBLIC_URL) return String(process.env.PUBLIC_URL).replace(/\/$/, '');
  return `${req.protocol}://${req.get('host')}`;
}

// Bestanden staan ook op GitHub-releases; die gebruiken we bij voorkeur
// (een download via ngrok verbruikt de maandelijkse bandbreedte-limit).
const GITHUB_RELEASE = 'https://github.com/GamerWolfert/cyberwolfert/releases/download';

function releaseAsset(v, name) {
  return `${GITHUB_RELEASE}/v${v.version}/${name}`;
}

router.get('/version', (req, res) => {
  const v = loadVersion();
  const dir = downloadDir();
  const has = (f) => fs.existsSync(path.join(dir, f));
  const local = (f) => `${publicBase(req)}/downloads/${f}`;
  res.json({
    ...v,
    downloads: {
      apk: releaseAsset(v, 'AeroSurf.apk'),
      windows: releaseAsset(v, 'AeroSurf-Windows.zip'),
      ios: v.iosUrl || null,
      bundle: releaseAsset(v, 'AeroSurf-apps.zip'),
      apkLocal: has('AeroSurf.apk') ? local('AeroSurf.apk') : null,
      bundleLocal: has('AeroSurf-apps.zip') ? local('AeroSurf-apps.zip') : null,
    },
  });
});

// Nieuwe gebeurtenissen sinds ?since=<epoch-seconden>: DM's, groepsberichten,
// ongelezen mail en vriendschapsverzoeken. Gebruikt voor meldingsgeluiden en
// systeemmeldingen (app én website).
router.get('/notify/events', async (req, res) => {
  if (!req.userId) return res.status(401).json({ error: 'login vereist' });
  const now = Math.floor(Date.now() / 1000);
  let since = Number(req.query.since || 0);
  if (!Number.isFinite(since) || since <= 0) since = now - 120;
  const t = new Date(since * 1000);
  try {
    const [dms, groups, mails, friends] = await Promise.all([
      db.query(
        `SELECT m.id, m.body, m.created_at,
                COALESCE(p.display_name, u.display_name, u.username) AS from_name
         FROM ws_dms m JOIN users u ON u.id=m.from_id
         LEFT JOIN ws_profiles p ON p.user_id=m.from_id
         WHERE m.to_id=$1 AND m.from_id<>$1 AND m.created_at > $2
         ORDER BY m.created_at DESC LIMIT 8`,
        [req.userId, t]
      ),
      db.query(
        `SELECT m.id, m.body, m.created_at, g.name AS group_name,
                COALESCE(p.display_name, u.display_name, u.username) AS from_name
         FROM ws_group_messages m
         JOIN ws_groups g ON g.id=m.group_id
         JOIN users u ON u.id=m.user_id
         LEFT JOIN ws_profiles p ON p.user_id=m.user_id
         WHERE m.user_id<>$1 AND m.created_at > $2
           AND EXISTS (SELECT 1 FROM ws_group_members gm
                       WHERE gm.group_id=m.group_id AND gm.user_id=$1)
         ORDER BY m.created_at DESC LIMIT 8`,
        [req.userId, t]
      ),
      db.query(
        `SELECT mm.id, mm.subject, mm.from_addr, mm.received_at
         FROM mail_messages mm JOIN mail_mailboxes mb ON mb.id=mm.mailbox_id
         WHERE mm.dir='in' AND mm.is_read=false AND mm.received_at > $2
           AND (mb.owner_user_id=$1
                OR EXISTS (SELECT 1 FROM mail_access a
                           WHERE a.mailbox_id=mb.id AND a.user_id=$1))
         ORDER BY mm.received_at DESC LIMIT 8`,
        [req.userId, t]
      ),
      db.query(
        `SELECT r.id, r.created_at,
                COALESCE(p.display_name, u.display_name, u.username) AS from_name
         FROM ws_friend_requests r JOIN users u ON u.id=r.from_id
         LEFT JOIN ws_profiles p ON p.user_id=r.from_id
         WHERE r.to_id=$1 AND r.status='pending' AND r.created_at > $2
         ORDER BY r.created_at DESC LIMIT 5`,
        [req.userId, t]
      ),
    ]);
    const slim = (r) =>
      r.rows.map((x) => ({
        id: x.id,
        body: String(x.body || x.subject || '').replace(/\s+/g, ' ').slice(0, 160),
        from: x.from_name || x.from_addr || '',
        group: x.group_name || null,
        at: x.created_at,
      }));
    res.json({
      now,
      dms: slim(dms),
      groups: slim(groups),
      mails: slim(mails),
      friends: slim(friends),
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'notify_failed' });
  }
});

// Huidige externe tunnel-URL (wordt door tunnel-watch.sh weggeschreven).
router.get('/tunnel', (req, res) => {
  try {
    res.type('json').send(fs.readFileSync(path.join(__dirname, '..', '..', 'tunnel.json'), 'utf8'));
  } catch {
    res.json({ url: null });
  }
});

router.get('/update-check', (req, res) => {
  const v = loadVersion();
  const build = Number(req.query.build || 0);
  res.json({
    current: { version: v.version, build: v.build, notes: v.notes },
    updateAvailable: build < Number(v.build || 0),
    forceUpdate: false,
  });
});

// POST /api/logs { secret, channel, text } -> direct een Discord-kanaal in.
router.post('/logs', async (req, res) => {
  const { secret, channel, text } = req.body || {};
  if (!process.env.LOG_SECRET || secret !== process.env.LOG_SECRET) {
    return res.status(403).json({ error: 'forbidden' });
  }
  const allowed = new Set(Object.values(CHANNELS).filter(Boolean));
  const id = CHANNELS[channel] || channel;
  if (!id || !allowed.has(String(id))) return res.status(400).json({ error: 'onbekend kanaal' });
  await send(String(id), String(text || '').slice(0, 1900));
  res.json({ ok: true });
});

module.exports = router;
