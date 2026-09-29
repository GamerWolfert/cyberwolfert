// Admin-API: gebruikers, rollen+permissies, logs, site-instellingen.
// Alleen voor is_admin of de juiste permissie (knop is alleen zichtbaar
// voor gamerwolfert en beheerders).
const express = require('express');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const db = require('../db');
const { PERMS, ALL_PERMS, effectivePerms, requirePerm } = require('../perms');
const router = express.Router();

function pub(u) {
  return {
    id: u.id, username: u.username,
    displayName: u.display_name || u.username,
    email: u.email || null, emailVerified: !!u.email_verified,
    is_admin: !!u.is_admin, created_at: u.created_at,
    provider: u.google_id ? 'google' : 'cyberwolfert',
  };
}

async function rolesOf(uid) {
  try {
    const r = await db.query(
      'SELECT role_name FROM site_user_roles WHERE user_id=$1', [uid]);
    return r.rows.map((x) => x.role_name);
  } catch {
    return [];
  }
}

// --- Overzicht ---
router.get('/overview', requirePerm('site.stats'), async (req, res) => {
  try {
    const q = async (sql, p = []) => (await db.query(sql, p)).rows[0];
    const users = await q('SELECT COUNT(*)::int AS n FROM users');
    const searches = await q(
      "SELECT COUNT(*)::int AS n FROM search_history WHERE created_at > NOW() - INTERVAL '24 hours'");
    const ai = await db.query(
      "SELECT COUNT(*)::int AS n FROM ai_chats WHERE created_at > NOW() - INTERVAL '24 hours'");
    const logins = await db.query(
      "SELECT COUNT(*)::int AS n FROM auth_events WHERE created_at > NOW() - INTERVAL '24 hours'");
    const servers = await db.query('SELECT COUNT(*)::int AS n FROM ws_servers');
    const v = require('fs').readFileSync(require('path').join(__dirname, '..', '..', 'version.json'), 'utf8');
    res.json({
      users: users.n, searches24h: searches.n, ai24h: ai.rows[0].n,
      logins24h: logins.rows[0].n, servers: servers.rows[0].n,
      version: JSON.parse(v), uptimeSec: Math.floor(process.uptime()),
    });
  } catch (e) {
    res.status(500).json({ error: 'overview_failed' });
  }
});

// --- Permissie-catalogus + eigen rechten ---
router.get('/perms', requirePerm('roles.view'), async (req, res) => {
  res.json({ groups: PERMS });
});
router.get('/me', async (req, res) => {
  const { authRequired } = require('./auth');
  return authRequired(req, res, async () => {
    res.json({ perms: await effectivePerms(db, req.userId) });
  });
});

// --- Gebruikers ---
router.get('/users', requirePerm('users.view'), async (req, res) => {
  const q = String(req.query.q || '').trim();
  const limit = Math.min(Number(req.query.limit || 50), 200);
  const r = await db.query(
    q
      ? `SELECT * FROM users WHERE username ILIKE $1 OR email ILIKE $1 OR display_name ILIKE $1 ORDER BY id LIMIT $2`
      : `SELECT * FROM users ORDER BY id DESC LIMIT $1`,
    q ? [`%${q}%`, limit] : [limit]
  );
  const out = [];
  for (const u of r.rows) {
    out.push({ ...pub(u), roles: await rolesOf(u.id) });
  }
  res.json(out);
});

router.get('/users/:id', requirePerm('users.view'), async (req, res) => {
  const r = await db.query('SELECT * FROM users WHERE id=$1', [req.params.id]);
  if (!r.rows.length) return res.status(404).json({ error: 'not_found' });
  const devices = await db.query(
    'SELECT device_id, label, banned, last_seen FROM devices WHERE user_id=$1 ORDER BY last_seen DESC LIMIT 20',
    [req.params.id]
  );
  const perms = await effectivePerms(db, Number(req.params.id));
  res.json({ ...pub(r.rows[0]), roles: await rolesOf(req.params.id), devices: devices.rows, perms: Object.keys(perms) });
});

router.post('/users/:id/ban-device', requirePerm('users.ban'), async (req, res) => {
  const { device_id } = req.body || {};
  if (device_id) {
    await db.query('UPDATE devices SET banned=true WHERE user_id=$1 AND device_id=$2', [req.params.id, device_id]);
  } else {
    await db.query('UPDATE devices SET banned=true WHERE user_id=$1', [req.params.id]);
  }
  res.json({ ok: true });
});

router.post('/users/:id/unban-device', requirePerm('users.ban'), async (req, res) => {
  const { device_id } = req.body || {};
  if (device_id) {
    await db.query('UPDATE devices SET banned=false WHERE user_id=$1 AND device_id=$2', [req.params.id, device_id]);
  } else {
    await db.query('UPDATE devices SET banned=false WHERE user_id=$1', [req.params.id]);
  }
  res.json({ ok: true });
});

router.delete('/users/:id', requirePerm('users.delete'), async (req, res) => {
  if (Number(req.params.id) === req.userId) {
    return res.status(400).json({ error: 'jezelf verwijderen kan niet' });
  }
  const t = await db.query('SELECT is_admin FROM users WHERE id=$1', [req.params.id]);
  if (t.rows[0]?.is_admin) {
    const me = await db.query('SELECT is_admin, username FROM users WHERE id=$1', [req.userId]);
    if (me.rows[0]?.username !== 'gamerwolfert') {
      return res.status(403).json({ error: 'alleen gamerwolfert mag admins verwijderen' });
    }
  }
  await db.query('DELETE FROM users WHERE id=$1', [req.params.id]);
  res.json({ ok: true });
});

router.post('/users/:id/verify', requirePerm('users.verify'), async (req, res) => {
  await db.query('UPDATE users SET email_verified=true, email_token=NULL WHERE id=$1', [req.params.id]);
  res.json({ ok: true });
});

router.post('/users/:id/reset-password', requirePerm('users.resetpw'), async (req, res) => {
  const temp = crypto.randomBytes(6).toString('base64url');
  const hash = await bcrypt.hash(temp, 10);
  await db.query('UPDATE users SET password_hash=$1 WHERE id=$2', [hash, req.params.id]);
  res.json({ ok: true, tempPassword: temp });
});

router.post('/users/:id/make-admin', requirePerm('users.make_admin'), async (req, res) => {
  await db.query('UPDATE users SET is_admin=true WHERE id=$1', [req.params.id]);
  res.json({ ok: true });
});

router.post('/users/:id/remove-admin', requirePerm('users.make_admin'), async (req, res) => {
  const t = await db.query('SELECT username FROM users WHERE id=$1', [req.params.id]);
  if (t.rows[0]?.username === 'gamerwolfert') {
    return res.status(400).json({ error: 'gamerwolfert blijft altijd admin' });
  }
  await db.query('UPDATE users SET is_admin=false WHERE id=$1', [req.params.id]);
  res.json({ ok: true });
});

router.post('/users', requirePerm('users.view'), async (req, res) => {
  const b = req.body || {};
  const username = String(b.username || '').trim().toLowerCase();
  const password = String(b.password || '');
  if (!/^[a-z0-9_.-]{3,32}$/.test(username)) {
    return res.status(400).json({ error: 'gebruikersnaam: 3-32 tekens (a-z, cijfers, _ . -)' });
  }
  if (password.length < 6) return res.status(400).json({ error: 'wachtwoord minimaal 6 tekens' });
  const exists = await db.query('SELECT 1 FROM users WHERE username=$1 OR email=$2', [username, b.email || null]);
  if (exists.rows.length) return res.status(400).json({ error: 'gebruikersnaam of e-mail bestaat al' });
  const hash = await bcrypt.hash(password, 10);
  const r = await db.query(
    `INSERT INTO users (username, display_name, email, password_hash, email_verified, is_admin, created_at)
     VALUES ($1,$2,$3,$4,true,$5,NOW()) RETURNING *`,
    [username, String(b.displayName || username).slice(0, 60), b.email || null, hash, !!b.is_admin]
  );
  res.status(201).json(pub(r.rows[0]));
});

router.put('/users/:id', requirePerm('users.view'), async (req, res) => {
  const b = req.body || {};
  const cur = await db.query('SELECT * FROM users WHERE id=$1', [req.params.id]);
  if (!cur.rows.length) return res.status(404).json({ error: 'not_found' });
  const u = cur.rows[0];
  if (u.username === 'gamerwolfert' && b.is_admin === false) {
    return res.status(400).json({ error: 'gamerwolfert blijft altijd admin' });
  }
  const r = await db.query(
    `UPDATE users SET display_name=$2, email=$3, email_verified=$4, is_admin=$5 WHERE id=$1 RETURNING *`,
    [
      req.params.id,
      String(b.displayName ?? u.display_name ?? u.username).slice(0, 60),
      b.email === undefined ? u.email : (b.email || null),
      b.emailVerified === undefined ? !!u.email_verified : !!b.emailVerified,
      b.is_admin === undefined ? !!u.is_admin : !!b.is_admin,
    ]
  );
  res.json(pub(r.rows[0]));
});

router.delete('/logs/searches', requirePerm('logs.search'), async (req, res) => {
  await db.query('DELETE FROM search_history');
  res.json({ ok: true });
});

router.delete('/logs/ai', requirePerm('logs.ai'), async (req, res) => {
  await db.query('DELETE FROM ai_chats');
  res.json({ ok: true });
});

router.post('/mail/test', requirePerm('mail.test'), async (req, res) => {
  const { sendMail, brief } = require('../mail');
  const to = String(req.body?.to || '').trim();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(to)) {
    return res.status(400).json({ error: 'geldig e-mailadres nodig' });
  }
  const out = await sendMail(to, 'CyberWolfert — testmail', brief({
    titel: 'Testmail geslaagd',
    intro: 'Dit is een testmail vanuit het CyberWolfert admin-paneel.',
    bodyHtml: '<p>Als je dit levert, werkt de SMTP-relay.</p>',
  }));
  res.json(out);
});

// --- Rollen ---
router.get('/roles', requirePerm('roles.view'), async (req, res) => {
  const r = await db.query('SELECT name, permissions FROM site_roles ORDER BY name');
  const users = await db.query(
    `SELECT role_name, COUNT(*)::int AS n FROM site_user_roles GROUP BY role_name`);
  const counts = Object.fromEntries(users.rows.map((x) => [x.role_name, x.n]));
  res.json(r.rows.map((x) => ({ ...x, users: counts[x.name] || 0 })));
});

router.post('/roles', requirePerm('roles.create'), async (req, res) => {
  const { name, permissions } = req.body || {};
  if (!name || !/^[a-z0-9_-]{2,32}$/i.test(name)) {
    return res.status(400).json({ error: 'rolnaam: 2-32 tekens, letters/cijfers/_/-' });
  }
  const valid = new Set(ALL_PERMS.map(([k]) => k));
  const clean = {};
  for (const k of Object.keys(permissions || {})) {
    if (valid.has(k) && permissions[k]) clean[k] = true;
  }
  const r = await db.query(
    'INSERT INTO site_roles (name, permissions) VALUES ($1,$2) ON CONFLICT (name) DO UPDATE SET permissions=EXCLUDED.permissions RETURNING *',
    [String(name).toLowerCase(), JSON.stringify(clean)]
  );
  res.json(r.rows[0]);
});

router.delete('/roles/:name', requirePerm('roles.delete'), async (req, res) => {
  if (['admin', 'user'].includes(req.params.name)) {
    return res.status(400).json({ error: 'systeemrol kan niet weg' });
  }
  await db.query('DELETE FROM site_roles WHERE name=$1', [req.params.name]);
  res.json({ ok: true });
});

router.post('/users/:id/roles', requirePerm('roles.assign'), async (req, res) => {
  const roles = Array.isArray(req.body?.roles) ? req.body.roles.map(String) : [];
  await db.query('DELETE FROM site_user_roles WHERE user_id=$1', [req.params.id]);
  for (const rn of roles) {
    await db.query(
      'INSERT INTO site_user_roles (user_id, role_name) SELECT $1,$2 WHERE EXISTS (SELECT 1 FROM site_roles WHERE name=$2) ON CONFLICT DO NOTHING',
      [req.params.id, rn]
    );
  }
  res.json({ ok: true, roles });
});

router.post('/users/:id/perms', requirePerm('perms.grant'), async (req, res) => {
  const { perm, allow } = req.body || {};
  if (!ALL_PERMS.some(([k]) => k === perm)) {
    return res.status(400).json({ error: 'onbekende permissie' });
  }
  await db.query(
    `INSERT INTO site_user_perms (user_id, perm, allow) VALUES ($1,$2,$3)
     ON CONFLICT (user_id, perm) DO UPDATE SET allow=EXCLUDED.allow`,
    [req.params.id, perm, !!allow]
  );
  res.json({ ok: true });
});

// --- Logs (live uit DB) ---
router.get('/logs/searches', requirePerm('logs.search'), async (req, res) => {
  const limit = Math.min(Number(req.query.limit || 50), 200);
  const r = await db.query(
    `SELECT h.query, h.created_at, COALESCE(u.username,'?') AS username
     FROM search_history h LEFT JOIN users u ON u.id=h.user_id
     ORDER BY h.created_at DESC LIMIT $1`, [limit]);
  res.json(r.rows);
});

router.get('/logs/ai', requirePerm('logs.ai'), async (req, res) => {
  const limit = Math.min(Number(req.query.limit || 50), 200);
  const r = await db.query(
    `SELECT c.role, LEFT(c.content, 220) AS content, c.created_at, COALESCE(u.username,'?') AS username
     FROM ai_chats c LEFT JOIN users u ON u.id=c.user_id
     ORDER BY c.created_at DESC LIMIT $1`, [limit]);
  res.json(r.rows);
});

router.get('/logs/logins', requirePerm('logs.logins'), async (req, res) => {
  const limit = Math.min(Number(req.query.limit || 50), 200);
  const r = await db.query(
    `SELECT e.kind, e.created_at, COALESCE(u.username, e.username, '?') AS username
     FROM auth_events e LEFT JOIN users u ON u.id=e.user_id
     ORDER BY e.created_at DESC LIMIT $1`, [limit]);
  res.json(r.rows);
});

// Verwijderde/verdwenen WolfSyn-berichten (berichten zelf zijn weg, log blijft).
router.get('/logs/wolfsyn', requirePerm('wolf.servers'), async (req, res) => {
  const limit = Math.min(Number(req.query.limit || 50), 200);
  const r = await db.query(
    `SELECT kind, ref_id, message_id, COALESCE(username, '?') AS username, body, reason, deleted_at
     FROM ws_message_log ORDER BY deleted_at DESC LIMIT $1`, [limit]);
  res.json(r.rows);
});

// --- Site ---
router.get('/site/settings', requirePerm('site.stats'), async (req, res) => {
  const r = await db.query('SELECT key, value FROM site_settings');
  res.json(Object.fromEntries(r.rows.map((x) => [x.key, x.value])));
});

router.put('/site/settings', requirePerm('site.announce'), async (req, res) => {
  const { announcement, options } = req.body || {};
  if (announcement !== undefined) {
    await db.query(
      `INSERT INTO site_settings (key, value) VALUES ('announcement',$1)
       ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value`,
      [String(announcement || '').slice(0, 500)]
    );
  }
  if (options && typeof options === 'object') {
    await db.query(
      `INSERT INTO site_settings (key, value) VALUES ('admin_options',$1)
       ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value`,
      [JSON.stringify(options).slice(0, 60000)]
    );
  }
  res.json({ ok: true });
});

router.get('/site/public', async (req, res) => {
  try {
    const r = await db.query("SELECT value FROM site_settings WHERE key='announcement'");
    res.json({ announcement: r.rows[0]?.value || '' });
  } catch {
    res.json({ announcement: '' });
  }
});

module.exports = router;
