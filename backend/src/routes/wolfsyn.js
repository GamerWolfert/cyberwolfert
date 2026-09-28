// WolfSyn: Discord-achtige community, volledig geïntegreerd met browser-accounts.
// - Servers (groepen) maken + joinen via uitnodigingscode
// - Rollen met rechten (beheren/kicken), kanalen, berichten (polling)
// - DM's tussen gebruikers, eigen WolfSyn-profiel (naam/foto/bio)
// Alles vereist login (gast -> app stuurt naar browser-login).
const express = require('express');
const crypto = require('crypto');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const db = require('../db');
const { authRequired } = require('../auth');
const router = express.Router();

router.use(authRequired);

function code() {
  const abc = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  let s = '';
  crypto.randomFillSync;
  const b = crypto.randomBytes(8);
  for (let i = 0; i < 8; i++) s += abc[b[i] % abc.length];
  return s;
}

async function isOwner(uid, serverId) {
  const r = await db.query('SELECT 1 FROM ws_servers WHERE id=$1 AND owner_id=$2', [serverId, uid]);
  return r.rows.length > 0;
}

async function isMember(uid, serverId) {
  if (await isOwner(uid, serverId)) return true;
  const r = await db.query('SELECT 1 FROM ws_members WHERE server_id=$1 AND user_id=$2', [serverId, uid]);
  return r.rows.length > 0;
}

async function canDo(uid, serverId, right) {
  if (await isOwner(uid, serverId)) return true;
  const col = right === 'manage' ? 'can_manage' : 'can_kick';
  const r = await db.query(
    `SELECT 1 FROM ws_member_roles mr JOIN ws_roles ro ON ro.id=mr.role_id
     WHERE mr.server_id=$1 AND mr.user_id=$2 AND ro.${col}=true`,
    [serverId, uid]
  );
  return r.rows.length > 0;
}

function esc(s) {
  return String(s || '').slice(0, 2000);
}

// --- Servers ---
router.get('/servers', async (req, res) => {
  const r = await db.query(
    `SELECT s.*, (SELECT COUNT(*) FROM ws_members m WHERE m.server_id=s.id)::int AS members
     FROM ws_servers s LEFT JOIN ws_members m ON m.server_id=s.id AND m.user_id=$1
     WHERE s.owner_id=$1 OR m.user_id=$1 GROUP BY s.id ORDER BY s.created_at DESC`,
    [req.userId]
  );
  res.json(r.rows);
});

router.post('/servers', async (req, res) => {
  const name = esc(req.body?.name || 'Nieuwe server').slice(0, 64) || 'Nieuwe server';
  const invite = code();
  const s = await db.query(
    'INSERT INTO ws_servers (owner_id, name, invite_code) VALUES ($1,$2,$3) RETURNING *',
    [req.userId, name, invite]
  );
  const server = s.rows[0];
  await db.query(
    "INSERT INTO ws_roles (server_id, name, color, can_manage, can_kick, position) VALUES ($1,'Baas','#E63946',true,true,0)",
    [server.id]
  );
  await db.query('INSERT INTO ws_channels (server_id, name, position) VALUES ($1,$2,0)', [server.id, 'algemeen']);
  res.json(server);
});

router.post('/join', async (req, res) => {
  const c = String(req.body?.code || '').trim().toUpperCase();
  const s = await db.query('SELECT * FROM ws_servers WHERE invite_code=$1', [c]);
  if (!s.rows.length) return res.status(404).json({ error: 'code onbekend' });
  await db.query(
    'INSERT INTO ws_members (server_id, user_id) VALUES ($1,$2) ON CONFLICT DO NOTHING',
    [s.rows[0].id, req.userId]
  );
  res.json(s.rows[0]);
});

router.get('/servers/:id', async (req, res) => {
  if (!(await isMember(req.userId, req.params.id))) return res.status(403).json({ error: 'geen lid' });
  const s = await db.query('SELECT * FROM ws_servers WHERE id=$1', [req.params.id]);
  const roles = await db.query('SELECT * FROM ws_roles WHERE server_id=$1 ORDER BY position', [req.params.id]);
  const members = await db.query(
    `SELECT u.id, u.username, COALESCE(p.display_name, u.display_name, u.username) AS display,
            COALESCE(p.avatar_url, u.avatar_url) AS avatar,
            COALESCE(array_agg(mr.role_id) FILTER (WHERE mr.role_id IS NOT NULL), '{}') AS roles
     FROM ws_members m JOIN users u ON u.id=m.user_id
     LEFT JOIN ws_profiles p ON p.user_id=u.id
     LEFT JOIN ws_member_roles mr ON mr.server_id=m.server_id AND mr.user_id=m.user_id
     WHERE m.server_id=$1 GROUP BY u.id, p.display_name, p.avatar_url, u.display_name, u.username`,
    [req.params.id]
  );
  const mine = await db.query(
    `SELECT COALESCE(bool_or(ro.can_manage), false) AS manage, COALESCE(bool_or(ro.can_kick), false) AS kick
     FROM ws_member_roles mr JOIN ws_roles ro ON ro.id=mr.role_id
     WHERE mr.server_id=$1 AND mr.user_id=$2`,
    [req.params.id, req.userId]
  );
  const owner = await isOwner(req.userId, req.params.id);
  res.json({
    server: s.rows[0],
    roles: roles.rows,
    members: members.rows,
    myRights: { manage: owner || !!mine.rows[0]?.manage, kick: owner || !!mine.rows[0]?.kick, owner },
  });
});

// --- Rollen ---
router.post('/servers/:id/roles', async (req, res) => {
  if (!(await canDo(req.userId, req.params.id, 'manage'))) {
    return res.status(403).json({ error: 'geen recht' });
  }
  const { name, color, can_manage, can_kick } = req.body || {};
  const r = await db.query(
    'INSERT INTO ws_roles (server_id, name, color, can_manage, can_kick, position) VALUES ($1,$2,$3,$4,$5,1) RETURNING *',
    [req.params.id, esc(name || 'Nieuw').slice(0, 32), String(color || '#29B6F6').slice(0, 16), !!can_manage, !!can_kick]
  );
  res.json(r.rows[0]);
});

router.put('/servers/:id/members/:uid/roles', async (req, res) => {
  if (!(await canDo(req.userId, req.params.id, 'manage'))) {
    return res.status(403).json({ error: 'geen recht' });
  }
  const ids = Array.isArray(req.body?.roleIds) ? req.body.roleIds.map(Number).filter(Boolean) : [];
  await db.query('DELETE FROM ws_member_roles WHERE server_id=$1 AND user_id=$2', [req.params.id, req.params.uid]);
  for (const rid of ids) {
    await db.query(
      'INSERT INTO ws_member_roles (server_id, user_id, role_id) SELECT $1,$2,$3 WHERE EXISTS (SELECT 1 FROM ws_roles WHERE id=$3 AND server_id=$1) ON CONFLICT DO NOTHING',
      [req.params.id, req.params.uid, rid]
    );
  }
  res.json({ ok: true });
});

router.delete('/servers/:id/members/:uid', async (req, res) => {
  const target = Number(req.params.uid);
  const ownerRow = await db.query('SELECT owner_id FROM ws_servers WHERE id=$1', [req.params.id]);
  if (ownerRow.rows[0]?.owner_id === target) return res.status(400).json({ error: 'eigenaar kan niet gekickt' });
  if (!(await canDo(req.userId, req.params.id, 'kick'))) {
    return res.status(403).json({ error: 'geen recht' });
  }
  await db.query('DELETE FROM ws_members WHERE server_id=$1 AND user_id=$2', [req.params.id, target]);
  await db.query('DELETE FROM ws_member_roles WHERE server_id=$1 AND user_id=$2', [req.params.id, target]);
  res.json({ ok: true });
});

// --- Kanalen + berichten ---
router.get('/servers/:id/channels', async (req, res) => {
  if (!(await isMember(req.userId, req.params.id))) return res.status(403).json({ error: 'geen lid' });
  const r = await db.query('SELECT * FROM ws_channels WHERE server_id=$1 ORDER BY position, id', [req.params.id]);
  res.json(r.rows);
});

router.post('/servers/:id/channels', async (req, res) => {
  if (!(await canDo(req.userId, req.params.id, 'manage'))) {
    return res.status(403).json({ error: 'geen recht' });
  }
  const r = await db.query('INSERT INTO ws_channels (server_id, name) VALUES ($1,$2) RETURNING *', [
    req.params.id,
    esc(req.body?.name || 'nieuw-kanaal').slice(0, 48).toLowerCase().replace(/\s+/g, '-'),
  ]);
  res.json(r.rows[0]);
});

async function channelServer(channelId) {
  const r = await db.query('SELECT server_id FROM ws_channels WHERE id=$1', [channelId]);
  return r.rows[0]?.server_id || null;
}

router.get('/channels/:id/messages', async (req, res) => {
  const sid = await channelServer(req.params.id);
  if (!sid || !(await isMember(req.userId, sid))) return res.status(403).json({ error: 'geen lid' });
  const limit = Math.min(Number(req.query.limit || 50), 100);
  const before = Number(req.query.before || 0);
  const r = await db.query(
    `SELECT m.*, COALESCE(p.display_name, u.display_name, u.username) AS display,
            COALESCE(p.avatar_url, u.avatar_url) AS avatar, u.username
     FROM ws_messages m JOIN users u ON u.id=m.user_id
     LEFT JOIN ws_profiles p ON p.user_id=u.id
     WHERE m.channel_id=$1 ${before ? 'AND m.id < $3' : ''} ORDER BY m.id DESC LIMIT $2`,
    before ? [req.params.id, limit, before] : [req.params.id, limit]
  );
  res.json(r.rows.reverse());
});

router.post('/channels/:id/messages', async (req, res) => {
  const sid = await channelServer(req.params.id);
  if (!sid || !(await isMember(req.userId, sid))) return res.status(403).json({ error: 'geen lid' });
  const body = esc(req.body?.body);
  if (!body) return res.status(400).json({ error: 'leeg bericht' });
  const r = await db.query(
    'INSERT INTO ws_messages (channel_id, user_id, body) VALUES ($1,$2,$3) RETURNING *',
    [req.params.id, req.userId, body]
  );
  res.json(r.rows[0]);
});

// --- Gebruikers zoeken (voor DM) ---
router.get('/users', async (req, res) => {
  const q = String(req.query.q || '').trim();
  if (q.length < 2) return res.json([]);
  const r = await db.query(
    `SELECT u.id, u.username, COALESCE(p.display_name, u.display_name, u.username) AS display,
            COALESCE(p.avatar_url, u.avatar_url) AS avatar
     FROM users u LEFT JOIN ws_profiles p ON p.user_id=u.id
     WHERE u.id != $2 AND (u.username ILIKE $1 OR COALESCE(p.display_name,'') ILIKE $1) LIMIT 10`,
    [`%${q}%`, req.userId]
  );
  res.json(r.rows);
});

// --- DM's ---
router.get('/dms/:uid', async (req, res) => {
  const other = Number(req.params.uid);
  const limit = Math.min(Number(req.query.limit || 50), 100);
  const before = Number(req.query.before || 0);
  const r = await db.query(
    `SELECT * FROM ws_dms WHERE ((from_id=$1 AND to_id=$2) OR (from_id=$2 AND to_id=$1))
     ${before ? 'AND id < $4' : ''} ORDER BY id DESC LIMIT $3`,
    before ? [req.userId, other, limit, before] : [req.userId, other, limit]
  );
  res.json(r.rows.reverse());
});

router.post('/dms/:uid', async (req, res) => {
  const body = esc(req.body?.body);
  if (!body) return res.status(400).json({ error: 'leeg bericht' });
  const r = await db.query('INSERT INTO ws_dms (from_id, to_id, body) VALUES ($1,$2,$3) RETURNING *', [
    req.userId,
    Number(req.params.uid),
    body,
  ]);
  res.json(r.rows[0]);
});

// inbox: laatste DM per gesprekspartner
router.get('/inbox', async (req, res) => {
  const r = await db.query(
    `SELECT DISTINCT ON (partner) * FROM (
       SELECT CASE WHEN from_id=$1 THEN to_id ELSE from_id END AS partner, body, created_at, id
       FROM ws_dms WHERE from_id=$1 OR to_id=$1
     ) t ORDER BY partner, id DESC`,
    [req.userId]
  );
  const out = [];
  for (const row of r.rows) {
    const u = await db.query(
      `SELECT u.id, u.username, COALESCE(p.display_name, u.display_name, u.username) AS display,
              COALESCE(p.avatar_url, u.avatar_url) AS avatar
       FROM users u LEFT JOIN ws_profiles p ON p.user_id=u.id WHERE u.id=$1`,
      [row.partner]
    );
    out.push({ user: u.rows[0], last: row.body, at: row.created_at });
  }
  res.json(out);
});

// --- Eigen WolfSyn-profiel (los van browser-loginnaam) ---
router.get('/profile', async (req, res) => {
  const r = await db.query(
    `SELECT u.id, u.username, COALESCE(p.display_name, u.display_name, u.username) AS display,
            COALESCE(p.avatar_url, u.avatar_url) AS avatar, COALESCE(p.bio,'') AS bio
     FROM users u LEFT JOIN ws_profiles p ON p.user_id=u.id WHERE u.id=$1`,
    [req.userId]
  );
  res.json(r.rows[0] || {});
});

router.put('/profile', async (req, res) => {
  const { display_name, bio } = req.body || {};
  await db.query(
    `INSERT INTO ws_profiles (user_id, display_name, bio, updated_at)
     VALUES ($1,$2,$3,NOW())
     ON CONFLICT (user_id) DO UPDATE SET
       display_name=COALESCE(EXCLUDED.display_name, ws_profiles.display_name),
       bio=COALESCE(EXCLUDED.bio, ws_profiles.bio), updated_at=NOW()`,
    [req.userId, display_name ? String(display_name).slice(0, 64) : null, bio ? String(bio).slice(0, 256) : null]
  );
  const r = await db.query('SELECT * FROM ws_profiles WHERE user_id=$1', [req.userId]);
  res.json(r.rows[0]);
});

const avatarUpload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      const d = path.join(__dirname, '..', '..', 'uploads');
      fs.mkdirSync(d, { recursive: true });
      cb(null, d);
    },
    filename: (req, file, cb) => {
      cb(null, `avatar-${req.userId}-${Date.now()}-` + String(file.originalname || 'img').replace(/[^a-zA-Z0-9._-]/g, '_'));
    },
  }),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => (/^image\//.test(file.mimetype) ? cb(null, true) : cb(new Error('Alleen afbeeldingen'))),
});

router.post('/avatar', avatarUpload.single('file'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'missing_file' });
  const base = process.env.PUBLIC_URL
    ? String(process.env.PUBLIC_URL).replace(/\/$/, '')
    : `${req.protocol}://${req.get('host')}`;
  const url = `${base}/uploads/${req.file.filename}`;
  await db.query(
    `INSERT INTO ws_profiles (user_id, avatar_url, updated_at) VALUES ($1,$2,NOW())
     ON CONFLICT (user_id) DO UPDATE SET avatar_url=EXCLUDED.avatar_url, updated_at=NOW()`,
    [req.userId, url]
  );
  res.json({ url });
});

module.exports = router;
