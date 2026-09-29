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
    const g = await db.query(
      `SELECT * FROM ws_group_messages WHERE expires_at IS NOT NULL AND expires_at <= NOW() ORDER BY id`
    );
    for (const row of g.rows) await purgeGroupMessage(row, 'expire', null);
    if (m.rows.length || d.rows.length || g.rows.length) {
      log.wolfsyn(
        `**${m.rows.length + d.rows.length + g.rows.length} bericht(en)** automatisch verdwenen na lezing +${EPHEMERAL_SECONDS}s`
      );
    }
  } catch (_) {}
}
const sweeper = setInterval(sweepEphemeral, 5000);
if (sweeper.unref) sweeper.unref();

// --- Servers ---
router.get('/servers', async (req, res) => {
  const r = await db.query(
    `SELECT s.*, (SELECT COUNT(*) FROM ws_members m WHERE m.server_id=s.id)::int AS members,
            (SELECT COUNT(*) FROM ws_boosts b WHERE b.server_id=s.id)::int AS boosts,
            EXISTS (SELECT 1 FROM ws_boosts b WHERE b.server_id=s.id AND b.user_id=$1) AS my_boost
     FROM ws_servers s
     WHERE s.owner_id=$1 OR EXISTS (SELECT 1 FROM ws_members m WHERE m.server_id=s.id AND m.user_id=$1)
     ORDER BY s.created_at DESC`,
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

// Server-tag: kort label achter je naam, alleen in die server (zoals Discord).
function cleanTag(v) {
  return String(v || '')
    .replace(/[^\p{L}\p{N}_\- ]/gu, '')
    .trim()
    .slice(0, 24);
}

router.post('/join', async (req, res) => {
  const c = String(req.body?.code || '').trim().toUpperCase();
  const s = await db.query('SELECT * FROM ws_servers WHERE invite_code=$1', [c]);
  if (!s.rows.length) return res.status(404).json({ error: 'code onbekend' });
  await db.query(
    'INSERT INTO ws_members (server_id, user_id) VALUES ($1,$2) ON CONFLICT DO NOTHING',
    [s.rows[0].id, req.userId]
  );
  const tag = cleanTag(req.body?.tag);
  if (tag) {
    await db.query('UPDATE ws_members SET server_tag=$3 WHERE server_id=$1 AND user_id=$2', [s.rows[0].id, req.userId, tag]);
  }
  res.json(s.rows[0]);
});

// Eigen server-tag (later wijzigen).
router.put('/servers/:id/tag', async (req, res) => {
  const sid = Number(req.params.id);
  if (!(await isMember(req.userId, sid))) return res.status(403).json({ error: 'geen lid' });
  const tag = cleanTag(req.body?.tag);
  await db.query('UPDATE ws_members SET server_tag=$3 WHERE server_id=$1 AND user_id=$2', [sid, req.userId, tag || null]);
  res.json({ ok: true, tag: tag || null });
});

// --- Boosts (gratis, alleen visuals) ---
function boostLevel(n) {
  return n >= 7 ? 2 : n >= 2 ? 1 : 0;
}

router.post('/servers/:id/boost', async (req, res) => {
  const sid = Number(req.params.id);
  if (!(await isMember(req.userId, sid))) return res.status(403).json({ error: 'geen lid' });
  const has = await db.query('SELECT 1 FROM ws_boosts WHERE server_id=$1 AND user_id=$2', [sid, req.userId]);
  if (has.rows.length) {
    await db.query('DELETE FROM ws_boosts WHERE server_id=$1 AND user_id=$2', [sid, req.userId]);
  } else {
    await db.query('INSERT INTO ws_boosts (server_id, user_id) VALUES ($1,$2) ON CONFLICT DO NOTHING', [sid, req.userId]);
  }
  const c = await db.query('SELECT COUNT(*)::int AS n FROM ws_boosts WHERE server_id=$1', [sid]);
  const boosts = c.rows[0].n;
  const level = boostLevel(boosts);
  await db.query('UPDATE ws_servers SET banner_color=$2 WHERE id=$1', [
    sid,
    ['#E63946', '#29B6F6', '#F4B400'][level],
  ]);
  res.json({ ok: true, boosts, level, mine: !has.rows.length });
});

router.get('/servers/:id', async (req, res) => {
  if (!(await isMember(req.userId, req.params.id))) return res.status(403).json({ error: 'geen lid' });
  const s = await db.query('SELECT * FROM ws_servers WHERE id=$1', [req.params.id]);
  const roles = await db.query('SELECT * FROM ws_roles WHERE server_id=$1 ORDER BY position', [req.params.id]);
  const members = await db.query(
    `SELECT u.id, u.username, COALESCE(p.display_name, u.display_name, u.username) AS display,
            COALESCE(p.avatar_url, u.avatar_url) AS avatar, m.server_tag AS tag,
            (u.last_seen > NOW() - interval '60 seconds') AS online, u.last_seen,
            COALESCE(array_agg(mr.role_id) FILTER (WHERE mr.role_id IS NOT NULL), '{}') AS roles
     FROM ws_members m JOIN users u ON u.id=m.user_id
     LEFT JOIN ws_profiles p ON p.user_id=u.id
     LEFT JOIN ws_member_roles mr ON mr.server_id=m.server_id AND mr.user_id=m.user_id
     WHERE m.server_id=$1 GROUP BY u.id, p.display_name, p.avatar_url, u.display_name, u.username, m.server_tag`,
    [req.params.id]
  );
  const mine = await db.query(
    `SELECT COALESCE(bool_or(ro.can_manage), false) AS manage, COALESCE(bool_or(ro.can_kick), false) AS kick
     FROM ws_member_roles mr JOIN ws_roles ro ON ro.id=mr.role_id
     WHERE mr.server_id=$1 AND mr.user_id=$2`,
    [req.params.id, req.userId]
  );
  const owner = await isOwner(req.userId, req.params.id);
  const bc = await db.query('SELECT COUNT(*)::int AS n, BOOL_OR(user_id=$2) AS mine FROM ws_boosts WHERE server_id=$1', [
    req.params.id,
    req.userId,
  ]);
  const boosts = bc.rows[0]?.n || 0;
  const me = await db.query('SELECT server_tag FROM ws_members WHERE server_id=$1 AND user_id=$2', [
    req.params.id,
    req.userId,
  ]);
  res.json({
    server: s.rows[0],
    roles: roles.rows,
    members: members.rows,
    myRights: { manage: owner || !!mine.rows[0]?.manage, kick: owner || !!mine.rows[0]?.kick, owner },
    myTag: me.rows[0]?.server_tag || null,
    boost: { boosts, level: boostLevel(boosts), mine: !!bc.rows[0]?.mine },
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
            COALESCE(p.avatar_url, u.avatar_url) AS avatar, u.username,
            mm.server_tag AS tag
     FROM ws_messages m JOIN users u ON u.id=m.user_id
     LEFT JOIN ws_profiles p ON p.user_id=u.id
     LEFT JOIN ws_members mm ON mm.user_id=m.user_id AND mm.server_id=$4
     WHERE m.channel_id=$1 AND ($3::int IS NULL OR m.id < $3)
     ORDER BY m.id DESC LIMIT $2`,
    [req.params.id, limit, before ? Number(before) : null, sid]
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
            COALESCE(p.avatar_url, u.avatar_url) AS avatar,
            (u.last_seen > NOW() - interval '60 seconds') AS online, u.last_seen
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
              COALESCE(p.avatar_url, u.avatar_url) AS avatar,
              (u.last_seen > NOW() - interval '60 seconds') AS online, u.last_seen
       FROM users u LEFT JOIN ws_profiles p ON p.user_id=u.id WHERE u.id=$1`,
      [row.partner]
    );
    out.push({ user: u.rows[0], last: row.body, at: row.created_at });
  }
  res.json(out);
});

// --- Vrienden (zoals Discord) ---
async function addFriend(a, b) {
  await db.query(
    `INSERT INTO ws_friends (user_id, friend_id) VALUES ($1,$2),($2,$1) ON CONFLICT DO NOTHING`,
    [a, b]
  );
  await db.query(`DELETE FROM ws_friend_requests WHERE (from_id=$1 AND to_id=$2) OR (from_id=$2 AND to_id=$1)`, [a, b]);
}

const friendCols = `u.id, u.username, COALESCE(p.display_name, u.display_name, u.username) AS display,
        COALESCE(p.avatar_url, u.avatar_url) AS avatar,
        (u.last_seen > NOW() - interval '60 seconds') AS online,
        u.last_seen`;
// Let m.id altijd de bericht-id zijn (friendCols bevat ook u.id).
const groupMsgCols = `m.id, m.group_id, m.user_id, m.body, m.expires_at, m.created_at, u.username,
        COALESCE(p.display_name, u.display_name, u.username) AS display,
        COALESCE(p.avatar_url, u.avatar_url) AS avatar`;

router.get('/friends', async (req, res) => {
  const friends = await db.query(
    `SELECT ${friendCols}, f.since FROM ws_friends f JOIN users u ON u.id=f.friend_id
     LEFT JOIN ws_profiles p ON p.user_id=u.id WHERE f.user_id=$1
     ORDER BY LOWER(COALESCE(p.display_name, u.display_name, u.username))`,
    [req.userId]
  );
  const incoming = await db.query(
    `SELECT r.id AS request_id, r.created_at, ${friendCols} FROM ws_friend_requests r
     JOIN users u ON u.id=r.from_id LEFT JOIN ws_profiles p ON p.user_id=u.id
     WHERE r.to_id=$1 AND r.status='pending' ORDER BY r.created_at DESC`,
    [req.userId]
  );
  const outgoing = await db.query(
    `SELECT r.id AS request_id, r.created_at, ${friendCols} FROM ws_friend_requests r
     JOIN users u ON u.id=r.to_id LEFT JOIN ws_profiles p ON p.user_id=u.id
     WHERE r.from_id=$1 AND r.status='pending' ORDER BY r.created_at DESC`,
    [req.userId]
  );
  res.json({ friends: friends.rows, incoming: incoming.rows, outgoing: outgoing.rows });
});

router.post('/friends/request', async (req, res) => {
  const uname = String(req.body?.username || '').trim();
  if (!uname) return res.status(400).json({ error: 'naam ontbreekt' });
  const u = await db.query('SELECT id FROM users WHERE LOWER(username)=LOWER($1)', [uname]);
  if (!u.rows.length) return res.status(404).json({ error: 'gebruiker niet gevonden' });
  const other = Number(u.rows[0].id);
  if (other === req.userId) return res.status(400).json({ error: 'je kan jezelf geen verzoek sturen' });
  const are = await db.query('SELECT 1 FROM ws_friends WHERE user_id=$1 AND friend_id=$2', [req.userId, other]);
  if (are.rows.length) return res.status(409).json({ error: 'jullie zijn al vrienden' });
  const rev = await db.query(
    `SELECT 1 FROM ws_friend_requests WHERE from_id=$1 AND to_id=$2 AND status='pending'`,
    [other, req.userId]
  );
  if (rev.rows.length) {
    await addFriend(req.userId, other);
    return res.json({ ok: true, accepted: true });
  }
  await db.query(
    `INSERT INTO ws_friend_requests (from_id, to_id) VALUES ($1,$2)
     ON CONFLICT (from_id, to_id) DO UPDATE SET status='pending', created_at=NOW()`,
    [req.userId, other]
  );
  res.json({ ok: true, sent: true });
});

router.post('/friends/respond', async (req, res) => {
  const from = Number(req.body?.from ?? req.body?.from_id);
  const accept = req.body?.accept !== false;
  const r = await db.query(
    `SELECT * FROM ws_friend_requests WHERE from_id=$1 AND to_id=$2 AND status='pending'`,
    [from, req.userId]
  );
  if (!r.rows.length) return res.status(404).json({ error: 'geen verzoek gevonden' });
  if (accept) {
    await db.query(`UPDATE ws_friend_requests SET status='accepted' WHERE id=$1`, [r.rows[0].id]);
    await addFriend(req.userId, from);
  } else {
    await db.query('DELETE FROM ws_friend_requests WHERE id=$1', [r.rows[0].id]);
  }
  res.json({ ok: true, accepted: accept });
});

router.delete('/friends/:uid', async (req, res) => {
  const other = Number(req.params.uid);
  await db.query('DELETE FROM ws_friends WHERE (user_id=$1 AND friend_id=$2) OR (user_id=$2 AND friend_id=$1)', [
    req.userId,
    other,
  ]);
  await db.query(
    `DELETE FROM ws_friend_requests WHERE (from_id=$1 AND to_id=$2) OR (from_id=$2 AND to_id=$1)`,
    [req.userId, other]
  );
  res.json({ ok: true });
});

// --- Groeps-DM's (groepen met vrienden) ---
async function groupMemberIds(gid) {
  const r = await db.query('SELECT user_id FROM ws_group_members WHERE group_id=$1', [gid]);
  return r.rows.map((x) => Number(x.user_id));
}

async function isGroupMember(uid, gid) {
  const r = await db.query('SELECT 1 FROM ws_group_members WHERE group_id=$1 AND user_id=$2', [gid, uid]);
  return r.rows.length > 0;
}

// Zet expires_at als ALLES het groepsbericht gelezen heeft.
async function markGroupRead(gid, uid, ids) {
  const list = (ids || []).map(Number).filter((n) => n > 0);
  if (!list.length) return [];
  try {
    await db.query(
      `INSERT INTO ws_group_reads (message_id, user_id)
       SELECT unnest($1::int[]), $2 ON CONFLICT DO NOTHING`,
      [list, uid]
    );
    const members = await groupMemberIds(gid);
    if (!members.length) return [];
    const r = await db.query(
      `SELECT m.id FROM ws_group_messages m
        WHERE m.group_id=$1 AND m.expires_at IS NULL AND m.id = ANY($2::int[])
          AND NOT EXISTS (
            SELECT 1 FROM unnest($3::int[]) x(id)
             WHERE NOT EXISTS (
               SELECT 1 FROM ws_group_reads rr WHERE rr.message_id = m.id AND rr.user_id = x.id
             )
          )`,
      [gid, list, members]
    );
    if (r.rows.length) {
      const upd = await db.query(
        `UPDATE ws_group_messages SET expires_at = NOW() + ($2 || ' seconds')::interval
          WHERE id = ANY($1::int[]) RETURNING id, expires_at`,
        [r.rows.map((x) => x.id), String(EPHEMERAL_SECONDS)]
      );
      return upd.rows;
    }
  } catch (_) {}
  return [];
}

async function purgeGroupMessage(row, reason, byUid) {
  try {
    const u = await db.query('SELECT username FROM users WHERE id=$1', [row.user_id]);
    await db.query(
      `INSERT INTO ws_message_log (kind, ref_id, message_id, user_id, username, body, reason)
       VALUES ('group',$1,$2,$3,$4,$5,$6)`,
      [row.group_id, row.id, row.user_id, u.rows[0]?.username || null, row.body, reason]
    );
    await db.query('DELETE FROM ws_group_messages WHERE id=$1', [row.id]);
    if (reason !== 'expire') {
      const wie = byUid ? `door \`user#${byUid}\`` : 'automatisch';
      log.wolfsyn(
        `**WolfSyn groepsbericht verwijderd** (${wie}) groep #${row.group_id}: ` +
          String(row.body || '').replace(/\n/g, ' ').slice(0, 300)
      );
    }
    return true;
  } catch (_) {
    return false;
  }
}

router.post('/groups', async (req, res) => {
  const name = esc(req.body?.name || 'Nieuwe groep').slice(0, 64) || 'Nieuwe groep';
  const ids = (Array.isArray(req.body?.memberIds) ? req.body.memberIds : [])
    .map(Number)
    .filter((n) => n > 0 && n !== req.userId);
  if (!ids.length) return res.status(400).json({ error: 'kies minstens één vriend' });
  // Alleen echte vrienden mogen in een groep.
  const ok = await db.query('SELECT friend_id FROM ws_friends WHERE user_id=$1 AND friend_id = ANY($2::int[])', [
    req.userId,
    ids,
  ]);
  const allowed = new Set(ok.rows.map((x) => Number(x.friend_id)));
  const members = [...new Set([...ids].filter((x) => allowed.has(x)))].slice(0, 9);
  if (!members.length) return res.status(400).json({ error: 'alleen met vrienden (stuur eerst een vriendverzoek)' });
  const g = await db.query('INSERT INTO ws_groups (name, owner_id) VALUES ($1,$2) RETURNING *', [name, req.userId]);
  const gid = g.rows[0].id;
  await db.query('INSERT INTO ws_group_members (group_id, user_id) VALUES ($1,$2)', [gid, req.userId]);
  for (const m of members) {
    await db.query('INSERT INTO ws_group_members (group_id, user_id) VALUES ($1,$2) ON CONFLICT DO NOTHING', [gid, m]);
  }
  res.json(g.rows[0]);
});

router.get('/groups', async (req, res) => {
  const r = await db.query(
    `SELECT g.*, (SELECT COUNT(*) FROM ws_group_members x WHERE x.group_id=g.id)::int AS members,
            (SELECT b.body FROM ws_group_messages b WHERE b.group_id=g.id ORDER BY b.id DESC LIMIT 1) AS last_body,
            (SELECT b.created_at FROM ws_group_messages b WHERE b.group_id=g.id ORDER BY b.id DESC LIMIT 1) AS last_at,
            COALESCE((SELECT array_agg(u.username) FROM ws_group_members x JOIN users u ON u.id=x.user_id
                       WHERE x.group_id=g.id AND x.user_id != $1), '{}') AS member_names
     FROM ws_groups g JOIN ws_group_members mine ON mine.group_id=g.id AND mine.user_id=$1
     ORDER BY g.id DESC`,
    [req.userId]
  );
  res.json(r.rows);
});

router.get('/groups/:id', async (req, res) => {
  const gid = Number(req.params.id);
  if (!(await isGroupMember(req.userId, gid))) return res.status(403).json({ error: 'geen lid' });
  const g = await db.query('SELECT * FROM ws_groups WHERE id=$1', [gid]);
  if (!g.rows.length) return res.status(404).json({ error: 'groep niet gevonden' });
  const members = await db.query(
    `SELECT ${friendCols} FROM ws_group_members gm JOIN users u ON u.id=gm.user_id
     LEFT JOIN ws_profiles p ON p.user_id=u.id WHERE gm.group_id=$1 ORDER BY LOWER(COALESCE(p.display_name,u.display_name,u.username))`,
    [gid]
  );
  const limit = Math.min(Number(req.query.limit || 50), 100);
  const r = await db.query(
    `SELECT ${groupMsgCols} FROM ws_group_messages m JOIN users u ON u.id=m.user_id
     LEFT JOIN ws_profiles p ON p.user_id=u.id WHERE m.group_id=$1 ORDER BY m.id DESC LIMIT $2`,
    [gid, limit]
  );
  const rows = r.rows.reverse();
  const tick = await markGroupRead(gid, req.userId, rows.map((x) => x.id));
  if (tick.length) {
    const mp = new Map(tick.map((x) => [x.id, x.expires_at]));
    for (const row of rows) if (mp.has(row.id)) row.expires_at = mp.get(row.id);
  }
  res.json({ group: g.rows[0], members: members.rows, messages: rows });
});

router.post('/groups/:id/messages', async (req, res) => {
  const gid = Number(req.params.id);
  if (!(await isGroupMember(req.userId, gid))) return res.status(403).json({ error: 'geen lid' });
  const body = esc(req.body?.body);
  if (!body) return res.status(400).json({ error: 'leeg bericht' });
  if (/^\/delete\b/i.test(body)) {
    const g = await db.query('SELECT owner_id FROM ws_groups WHERE id=$1', [gid]);
    const allowed = g.rows[0]?.owner_id === req.userId || (await isAdminUser(req.userId));
    if (!allowed) return res.status(403).json({ error: 'alleen de maker van de groep mag /delete gebruiken' });
    const arg = body.replace(/^\/delete\s*/i, '').trim();
    const target = /^\d+$/.test(arg)
      ? await db.query('SELECT * FROM ws_group_messages WHERE id=$1 AND group_id=$2', [Number(arg), gid])
      : await db.query('SELECT * FROM ws_group_messages WHERE group_id=$1 ORDER BY id DESC LIMIT 1', [gid]);
    if (!target.rows.length) return res.status(404).json({ error: 'niets om te verwijderen' });
    await purgeGroupMessage(target.rows[0], 'owner_delete', req.userId);
    return res.json({ ok: true, deleted: target.rows[0].id });
  }
  const r = await db.query('INSERT INTO ws_group_messages (group_id, user_id, body) VALUES ($1,$2,$3) RETURNING *', [
    gid,
    req.userId,
    body,
  ]);
  res.json(r.rows[0]);
});

router.post('/groups/:id/leave', async (req, res) => {
  const gid = Number(req.params.id);
  await db.query('DELETE FROM ws_group_members WHERE group_id=$1 AND user_id=$2', [gid, req.userId]);
  const rest = await db.query('SELECT COUNT(*)::int AS n FROM ws_group_members WHERE group_id=$1', [gid]);
  if (!rest.rows[0]?.n) await db.query('DELETE FROM ws_groups WHERE id=$1', [gid]);
  res.json({ ok: true });
});

// --- Eigen WolfSyn-profiel (los van browser-loginnaam) ---
router.get('/profile', async (req, res) => {
  const r = await db.query(
    `SELECT u.id, u.username, COALESCE(p.display_name, u.display_name, u.username) AS display,
            COALESCE(p.avatar_url, u.avatar_url) AS avatar, COALESCE(p.bio,'') AS bio,
            u.last_seen, (u.last_seen > NOW() - interval '60 seconds') AS online
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
