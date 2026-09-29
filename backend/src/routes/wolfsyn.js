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
const { log } = require('../discord');
const router = express.Router();

router.use(authRequired);

// Berichten verdwijnen zodra iedereen ze gelezen heeft + dit aantal seconden.
const EPHEMERAL_SECONDS = 20;

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

// --- Verdwijnende berichten (WolfSyn) ---
async function isAdminUser(uid) {
  try {
    const r = await db.query('SELECT is_admin FROM users WHERE id=$1', [uid]);
    return !!r.rows[0]?.is_admin;
  } catch {
    return false;
  }
}

async function membersOf(sid) {
  const r = await db.query(
    `SELECT owner_id AS id FROM ws_servers WHERE id=$1
     UNION SELECT user_id FROM ws_members WHERE server_id=$1`,
    [sid]
  );
  return r.rows.map((x) => Number(x.id));
}

// Markeert berichten als gelezen door uid en zet expires_at als ALLES gelezen is.
async function markChannelRead(channelId, uid, messageIds) {
  const ids = (messageIds || []).map(Number).filter((n) => n > 0);
  if (!ids.length) return [];
  try {
    const sid = await channelServer(channelId);
    if (!sid) return [];
    await db.query(
      `INSERT INTO ws_message_reads (message_id, user_id)
       SELECT unnest($1::int[]), $2 ON CONFLICT DO NOTHING`,
      [ids, uid]
    );
    const members = await membersOf(sid);
    if (!members.length) return [];
    const r = await db.query(
      `SELECT m.id FROM ws_messages m
        WHERE m.channel_id=$1 AND m.expires_at IS NULL AND m.id = ANY($2::int[])
          AND NOT EXISTS (
            SELECT 1 FROM unnest($3::int[]) x(id)
             WHERE NOT EXISTS (
               SELECT 1 FROM ws_message_reads rr WHERE rr.message_id = m.id AND rr.user_id = x.id
             )
          )`,
      [channelId, ids, members]
    );
    if (r.rows.length) {
      const upd = await db.query(
        `UPDATE ws_messages SET expires_at = NOW() + ($2 || ' seconds')::interval
          WHERE id = ANY($1::int[]) RETURNING id, expires_at`,
        [r.rows.map((x) => x.id), String(EPHEMERAL_SECONDS)]
      );
      return upd.rows;
    }
  } catch (_) {}
  return [];
}

// Verwijderen + bewaren in ws_message_log (admin-paneel) en Discord.
async function purgeMessage(row, kind, refId, reason, byUid) {
  try {
    const u = await db.query('SELECT username FROM users WHERE id=$1', [row.user_id]);
    await db.query(
      `INSERT INTO ws_message_log (kind, ref_id, message_id, user_id, username, body, reason)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [kind, refId, row.id, row.user_id, u.rows[0]?.username || null, row.body, reason]
    );
    await db.query('DELETE FROM ws_messages WHERE id=$1', [row.id]);
    if (reason !== 'expire') {
      const wie = byUid ? `door \`user#${byUid}\`` : 'automatisch';
      log.wolfsyn(
        `**WolfSyn bericht verwijderd** (${wie}) in kanaal #${refId}: ` +
          String(row.body || '').replace(/\n/g, ' ').slice(0, 300)
      );
    }
    return true;
  } catch (_) {
    return false;
  }
}

async function purgeDm(row, reason, byUid) {
  try {
    const u = await db.query('SELECT username FROM users WHERE id=$1', [row.from_id]);
    await db.query(
      `INSERT INTO ws_message_log (kind, ref_id, message_id, user_id, username, body, reason)
       VALUES ('dm',$1,$2,$3,$4,$5,$6)`,
      [row.to_id, row.id, row.from_id, u.rows[0]?.username || null, row.body, reason]
    );
    await db.query('DELETE FROM ws_dms WHERE id=$1', [row.id]);
    if (reason !== 'expire') {
      const wie = byUid ? `door \`user#${byUid}\`` : 'automatisch';
      log.wolfsyn(
        `**WolfSyn DM verwijderd** (${wie}) user#${row.from_id} -> user#${row.to_id}: ` +
          String(row.body || '').replace(/\n/g, ' ').slice(0, 300)
      );
    }
    return true;
  } catch (_) {
    return false;
  }
}

// Ruimt alles op waar de teller verstreken is (elke 5 seconden).
async function sweepEphemeral() {
  try {
    const m = await db.query(
      `SELECT * FROM ws_messages WHERE expires_at IS NOT NULL AND expires_at <= NOW() ORDER BY id`
    );
    for (const row of m.rows) await purgeMessage(row, 'channel', row.channel_id, 'expire', null);
    const d = await db.query(`SELECT * FROM ws_dms WHERE expires_at IS NOT NULL AND expires_at <= NOW() ORDER BY id`);
    for (const row of d.rows) await purgeDm(row, 'expire', null);
    if (m.rows.length || d.rows.length) {
      log.wolfsyn(`**${m.rows.length + d.rows.length} bericht(en)** automatisch verdwenen na lezing +${EPHEMERAL_SECONDS}s`);
    }
  } catch (_) {}
}
const sweeper = setInterval(sweepEphemeral, 5000);
if (sweeper.unref) sweeper.unref();

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
  const rows = r.rows.reverse();
  // Lezen = markeren; als iedereen gelezen heeft, start de teller van 20 seconden.
  const tick = await markChannelRead(req.params.id, req.userId, rows.map((x) => x.id));
  if (tick.length) {
    const m = new Map(tick.map((x) => [x.id, x.expires_at]));
    for (const row of rows) if (m.has(row.id)) row.expires_at = m.get(row.id);
  }
  res.json(rows);
});

router.post('/channels/:id/messages', async (req, res) => {
  const sid = await channelServer(req.params.id);
  if (!sid || !(await isMember(req.userId, sid))) return res.status(403).json({ error: 'geen lid' });
  const body = esc(req.body?.body);
  if (!body) return res.status(400).json({ error: 'leeg bericht' });

  // /delete [id] -> eigenaar/moderator/admin wis meteen (log blijft bewaard).
  if (/^\/delete\b/i.test(body)) {
    const allowed =
      (await isOwner(req.userId, sid)) ||
      (await canDo(req.userId, sid, 'manage')) ||
      (await isAdminUser(req.userId));
    if (!allowed) return res.status(403).json({ error: 'alleen eigenaar of moderator mag /delete gebruiken' });
    const arg = body.replace(/^\/delete\s*/i, '').trim();
    let target;
    if (/^\d+$/.test(arg)) {
      target = await db.query('SELECT * FROM ws_messages WHERE id=$1 AND channel_id=$2', [Number(arg), req.params.id]);
    } else {
      target = await db.query('SELECT * FROM ws_messages WHERE channel_id=$1 ORDER BY id DESC LIMIT 1', [req.params.id]);
    }
    if (!target.rows.length) return res.status(404).json({ error: 'niets om te verwijderen' });
    const row = target.rows[0];
    await purgeMessage(row, 'channel', row.channel_id, 'owner_delete', req.userId);
    return res.json({ ok: true, deleted: row.id });
  }

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
  // Lezen = de conversatie openen: alles wat aan mij gestuurd is vervagt 20s hierna.
  await db.query(
    `UPDATE ws_dms SET expires_at = NOW() + ($3 || ' seconds')::interval
      WHERE from_id=$1 AND to_id=$2 AND expires_at IS NULL`,
    [other, req.userId, String(EPHEMERAL_SECONDS)]
  );
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
