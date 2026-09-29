// Eigen maildomeinen + mailboxen + inbox (hosted op de Mini-PC).
// - Admin ('mail.manage' of is_admin) maakt mailboxen aan, geeft gebruikers
//   toegang (read/full) of draagt het eigendom over.
// - Een gebruiker zonder rechten ziet alleen mailboxen waarvoor hij toegang kreeg
//   en kan daar vervolgens alles mee doen (lezen, sturen, wissen, toegang beheren).
// - Inkomend: eigen SMTP-server of webhook-relay. Uitgaand: MAIL_*-relay,
//   interne adressen worden direct lokaal bezorgd.
const express = require('express');
const crypto = require('crypto');
const db = require('../db');
const { authRequired } = require('../auth');
const { isAdmin, effectivePerms } = require('../perms');
const { deliverLocal, findMailbox, smtpStatus } = require('../smtp');
const { sendMail } = require('../mail');
const router = express.Router();

// Webhook (relay -> onze mailboxen) is een machine-endpoint: token i.p.v. login.
router.use((req, res, next) => {
  if (req.path === '/webhook') return next();
  return authRequired(req, res, next);
});

const LOCAL_RE = /^[a-z0-9][a-z0-9._-]{0,63}$/i;
const ADDR_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

async function manageFlag(uid) {
  if (await isAdmin(db, uid)) return true;
  const p = await effectivePerms(db, uid);
  return !!p['mail.manage'];
}

// Rol van deze gebruiker op een mailbox: owner | full | read | null (geen toegang).
async function roleOf(uid, mailboxId, manage) {
  if (manage) return 'owner';
  const r = await db.query(
    `SELECT COALESCE(
              (SELECT role FROM mail_access WHERE mailbox_id=$1 AND user_id=$2),
              (SELECT CASE WHEN owner_user_id=$2 THEN 'owner' END FROM mail_mailboxes WHERE id=$1)
            ) AS role`,
    [mailboxId, uid]
  );
  return r.rows[0]?.role || null;
}

async function needRole(req, res, mailboxId, min) {
  const manage = await manageFlag(req.userId);
  const role = await roleOf(req.userId, mailboxId, manage);
  if (!role) {
    res.status(403).json({ error: 'geen toegang tot deze mailbox' });
    return null;
  }
  const rank = { read: 1, full: 2, owner: 3 };
  if (rank[role] < rank[min]) {
    res.status(403).json({ error: 'onvoldoende rechten op deze mailbox' });
    return null;
  }
  req.mailRole = role;
  req.mailManage = manage;
  return role;
}

async function webhookToken() {
  const env = process.env.MAIL_WEBHOOK_TOKEN;
  if (env) return String(env);
  const r = await db.query("SELECT value FROM site_settings WHERE key='mail_webhook_token'");
  if (r.rows.length && r.rows[0].value) return r.rows[0].value;
  const t = crypto.randomBytes(24).toString('hex');
  await db.query(
    "INSERT INTO site_settings (key, value) VALUES ('mail_webhook_token', $1) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value",
    [t]
  );
  return t;
}

function escapeHtml(s) {
  return String(s || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

// ---------------- status & domeinen ----------------

router.get('/status', async (req, res) => {
  try {
    const manage = await manageFlag(req.userId);
    const dom = await db.query('SELECT * FROM mail_domains ORDER BY is_default DESC, domain');
    const mine = await db.query(
      'SELECT COUNT(*)::int AS n FROM mail_mailboxes WHERE owner_user_id=$1',
      [req.userId]
    );
    const relay = !!process.env.MAIL_HOST;
    res.json({
      manage,
      relay,
      smtp: smtpStatus(),
      webhookUrl: process.env.PUBLIC_URL
        ? `${String(process.env.PUBLIC_URL).replace(/\/$/, '')}/api/mail/webhook`
        : null,
      webhookToken: manage ? await webhookToken() : null,
      domains: dom.rows,
      myMailboxes: mine.rows[0].n,
    });
  } catch (e) {
    res.status(500).json({ error: 'status_mislukt', detail: e.message });
  }
});

router.get('/domains', async (req, res) => {
  const r = await db.query('SELECT * FROM mail_domains WHERE active ORDER BY is_default DESC, domain');
  res.json(r.rows);
});

router.post('/domains', async (req, res) => {
  if (!(await manageFlag(req.userId))) return res.status(403).json({ error: 'alleen admin' });
  const domain = String(req.body?.domain || '').trim().toLowerCase();
  if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/.test(domain)) {
    return res.status(400).json({ error: 'ongeldige domeinnaam' });
  }
  try {
    const r = await db.query(
      'INSERT INTO mail_domains (domain) VALUES ($1) ON CONFLICT (domain) DO UPDATE SET active=true RETURNING *',
      [domain]
    );
    res.json(r.rows[0]);
  } catch (e) {
    res.status(500).json({ error: 'domein_toevoegen_mislukt', detail: e.message });
  }
});

router.delete('/domains/:id', async (req, res) => {
  if (!(await manageFlag(req.userId))) return res.status(403).json({ error: 'alleen admin' });
  const boxes = await db.query('SELECT COUNT(*)::int AS n FROM mail_mailboxes WHERE domain_id=$1', [req.params.id]);
  if (boxes.rows[0].n > 0) return res.status(409).json({ error: 'domein bevat nog mailboxen' });
  await db.query('DELETE FROM mail_domains WHERE id=$1', [req.params.id]);
  res.json({ ok: true });
});

// ---------------- mailboxen ----------------

router.get('/mailboxes', async (req, res) => {
  try {
    const manage = await manageFlag(req.userId);
    const r = await db.query(
      `SELECT mb.id, mb.localpart, d.domain, mb.owner_user_id, mb.display_name, mb.created_at,
              LOWER(mb.localpart) || '@' || LOWER(d.domain) AS address,
              COALESCE(u.username, '') AS owner_username,
              CASE WHEN $2 THEN 'owner'
                   ELSE COALESCE(a.role, CASE WHEN mb.owner_user_id = $1 THEN 'owner' END)
              END AS role,
              (SELECT COUNT(*)::int FROM mail_messages m
                WHERE m.mailbox_id = mb.id AND m.dir = 'in' AND NOT m.is_read) AS unread,
              (SELECT COUNT(*)::int FROM mail_messages m WHERE m.mailbox_id = mb.id) AS total
         FROM mail_mailboxes mb
         JOIN mail_domains d ON d.id = mb.domain_id
         LEFT JOIN users u ON u.id = mb.owner_user_id
         LEFT JOIN mail_access a ON a.mailbox_id = mb.id AND a.user_id = $1
        WHERE $2 OR mb.owner_user_id = $1 OR a.user_id IS NOT NULL
        ORDER BY address`,
      [req.userId, manage]
    );
    res.json(r.rows);
  } catch (e) {
    res.status(500).json({ error: 'mailboxen_mislukt', detail: e.message });
  }
});

router.post('/mailboxes', async (req, res) => {
  if (!(await manageFlag(req.userId))) return res.status(403).json({ error: 'alleen admin' });
  const localpart = String(req.body?.localpart || '').trim();
  if (!LOCAL_RE.test(localpart)) {
    return res.status(400).json({ error: 'ongeldige naam (alleen letters, cijfers, . _ -)' });
  }
  try {
    let domainId = Number(req.body?.domain_id || 0);
    if (!domainId) {
      const d = await db.query('SELECT id FROM mail_domains WHERE is_default AND active LIMIT 1');
      domainId = d.rows[0]?.id;
    }
    if (!domainId) return res.status(400).json({ error: 'geen domein gekozen' });

    let ownerUid = null;
    const uname = String(req.body?.owner_username || '').trim();
    if (uname) {
      const u = await db.query('SELECT id FROM users WHERE LOWER(username)=LOWER($1)', [uname]);
      if (!u.rows.length) return res.status(404).json({ error: 'gebruiker bestaat niet' });
      ownerUid = u.rows[0].id;
    } else {
      ownerUid = req.userId;
    }

    const mb = await db.query(
      `INSERT INTO mail_mailboxes (localpart, domain_id, owner_user_id, display_name, created_by)
       VALUES ($1,$2,$3,$4,$5) RETURNING *`,
      [localpart, domainId, ownerUid, String(req.body?.display_name || '').slice(0, 128) || null, req.userId]
    );
    const row = mb.rows[0];
    await db.query(
      `INSERT INTO mail_access (mailbox_id, user_id, role, granted_by)
       VALUES ($1,$2,'owner',$3)
       ON CONFLICT (mailbox_id, user_id) DO UPDATE SET role='owner'`,
      [row.id, ownerUid, req.userId]
    );
    const addr = await db.query(
      'SELECT LOWER($1) || \'@\' || LOWER(d.domain) AS address FROM mail_domains d WHERE d.id=$2',
      [row.localpart, row.domain_id]
    );
    res.json({ ...row, address: addr.rows[0].address });
  } catch (e) {
    if (String(e.constraint || '').includes('mail_mailboxes')) {
      return res.status(409).json({ error: 'mailbox bestaat al' });
    }
    res.status(500).json({ error: 'mailbox_maken_mislukt', detail: e.message });
  }
});

router.delete('/mailboxes/:id', async (req, res) => {
  if (!(await manageFlag(req.userId))) return res.status(403).json({ error: 'alleen admin' });
  await db.query('DELETE FROM mail_mailboxes WHERE id=$1', [req.params.id]);
  res.json({ ok: true });
});

// ---------------- toegang & eigendom ----------------

router.get('/mailboxes/:id/access', async (req, res) => {
  const role = await needRole(req, res, Number(req.params.id), 'owner');
  if (!role) return;
  const r = await db.query(
    `SELECT a.user_id, a.role, a.created_at, u.username,
            COALESCE(u.display_name, u.username) AS display
       FROM mail_access a JOIN users u ON u.id = a.user_id
      WHERE a.mailbox_id = $1
      ORDER BY a.role, u.username`,
    [req.params.id]
  );
  const own = await db.query('SELECT owner_user_id FROM mail_mailboxes WHERE id=$1', [req.params.id]);
  res.json({ owner: own.rows[0]?.owner_user_id || null, access: r.rows });
});

router.post('/mailboxes/:id/access', async (req, res) => {
  const mailboxId = Number(req.params.id);
  const role = await needRole(req, res, mailboxId, 'owner');
  if (!role) return;
  const username = String(req.body?.username || '').trim();
  const want = String(req.body?.role || 'full');
  if (!['read', 'full'].includes(want)) return res.status(400).json({ error: 'rol moet read of full zijn' });
  const u = await db.query('SELECT id FROM users WHERE LOWER(username)=LOWER($1)', [username]);
  if (!u.rows.length) return res.status(404).json({ error: 'gebruiker bestaat niet' });
  await db.query(
    `INSERT INTO mail_access (mailbox_id, user_id, role, granted_by)
     VALUES ($1,$2,$3,$4)
     ON CONFLICT (mailbox_id, user_id) DO UPDATE SET role = EXCLUDED.role`,
    [mailboxId, u.rows[0].id, want, req.userId]
  );
  res.json({ ok: true, username, role: want });
});

router.delete('/mailboxes/:id/access/:uid', async (req, res) => {
  const mailboxId = Number(req.params.id);
  const role = await needRole(req, res, mailboxId, 'owner');
  if (!role) return;
  if (Number(req.params.uid) === req.userId && !req.mailManage) {
    return res.status(400).json({ error: 'je kunt je eigen toegang niet verwijderen (gebruik eigendom overdragen)' });
  }
  await db.query('DELETE FROM mail_access WHERE mailbox_id=$1 AND user_id=$2', [mailboxId, req.params.uid]);
  res.json({ ok: true });
});

router.post('/mailboxes/:id/transfer', async (req, res) => {
  const mailboxId = Number(req.params.id);
  const role = await needRole(req, res, mailboxId, 'owner');
  if (!role) return;
  const username = String(req.body?.username || '').trim();
  const u = await db.query('SELECT id, username FROM users WHERE LOWER(username)=LOWER($1)', [username]);
  if (!u.rows.length) return res.status(404).json({ error: 'gebruiker bestaat niet' });
  const newOwner = u.rows[0].id;
  const old = await db.query('SELECT owner_user_id FROM mail_mailboxes WHERE id=$1', [mailboxId]);
  const prevOwner = old.rows[0]?.owner_user_id || null;

  await db.query('BEGIN');
  try {
    await db.query('UPDATE mail_mailboxes SET owner_user_id=$1 WHERE id=$2', [newOwner, mailboxId]);
    await db.query(
      `INSERT INTO mail_access (mailbox_id, user_id, role, granted_by) VALUES ($1,$2,'owner',$3)
       ON CONFLICT (mailbox_id, user_id) DO UPDATE SET role='owner'`,
      [mailboxId, newOwner, req.userId]
    );
    if (prevOwner && prevOwner !== newOwner) {
      await db.query(
        `INSERT INTO mail_access (mailbox_id, user_id, role, granted_by) VALUES ($1,$2,'full',$3)
         ON CONFLICT (mailbox_id, user_id) DO UPDATE SET role = CASE WHEN mail_access.role='owner' THEN 'full' ELSE mail_access.role END`,
        [mailboxId, prevOwner, req.userId]
      );
    }
    await db.query('COMMIT');
  } catch (e) {
    await db.query('ROLLBACK');
    return res.status(500).json({ error: 'overdragen_mislukt', detail: e.message });
  }
  res.json({ ok: true, newOwner: u.rows[0].username });
});

// ---------------- inbox ----------------

router.get('/inbox/:mailboxId', async (req, res) => {
  const mailboxId = Number(req.params.mailboxId);
  const role = await needRole(req, res, mailboxId, 'read');
  if (!role) return;
  const box = String(req.query.box || 'in');
  const limit = Math.min(Number(req.query.limit || 50), 200);
  const r = await db.query(
    `SELECT m.id, m.dir, m.from_addr, m.to_addr, m.subject, m.is_read, m.code, m.received_at,
            LEFT(REGEXP_REPLACE(m.body_text, '\\s+', ' ', 'g'), 180) AS snippet
       FROM mail_messages m
      WHERE m.mailbox_id = $1 AND ($2 = 'all' OR m.dir = $2)
      ORDER BY m.received_at DESC, m.id DESC
      LIMIT $3`,
    [mailboxId, ['in', 'out', 'all'].includes(box) ? box : 'in', limit]
  );
  const unread = await db.query(
    'SELECT COUNT(*)::int AS n FROM mail_messages WHERE mailbox_id=$1 AND dir=$2 AND NOT is_read',
    [mailboxId, 'in']
  );
  res.json({ role, unread: unread.rows[0].n, messages: r.rows });
});

router.get('/messages/:id', async (req, res) => {
  const r = await db.query('SELECT * FROM mail_messages WHERE id=$1', [req.params.id]);
  if (!r.rows.length) return res.status(404).json({ error: 'bericht bestaat niet' });
  const m = r.rows[0];
  const role = await needRole(req, res, m.mailbox_id, 'read');
  if (!role) return;
  if (m.dir === 'in' && !m.is_read) {
    await db.query('UPDATE mail_messages SET is_read=true WHERE id=$1', [m.id]);
    m.is_read = true;
  }
  res.json(m);
});

router.delete('/messages/:id', async (req, res) => {
  const r = await db.query('SELECT mailbox_id FROM mail_messages WHERE id=$1', [req.params.id]);
  if (!r.rows.length) return res.status(404).json({ error: 'bericht bestaat niet' });
  const role = await needRole(req, res, r.rows[0].mailbox_id, 'full');
  if (!role) return;
  await db.query('DELETE FROM mail_messages WHERE id=$1', [req.params.id]);
  res.json({ ok: true });
});

router.post('/messages/:id/read', async (req, res) => {
  const r = await db.query('SELECT mailbox_id FROM mail_messages WHERE id=$1', [req.params.id]);
  if (!r.rows.length) return res.status(404).json({ error: 'bericht bestaat niet' });
  const role = await needRole(req, res, r.rows[0].mailbox_id, 'read');
  if (!role) return;
  await db.query('UPDATE mail_messages SET is_read=$2 WHERE id=$1', [req.params.id, req.body?.read !== false]);
  res.json({ ok: true });
});

// ---------------- sturen ----------------

router.post('/send', async (req, res) => {
  const mailboxId = Number(req.body?.mailbox_id || 0);
  const role = await needRole(req, res, mailboxId, 'full');
  if (!role) return;

  const to = String(req.body?.to || '').trim();
  const subject = String(req.body?.subject || '').slice(0, 900);
  const body = String(req.body?.body || '').slice(0, 100000);
  if (!ADDR_RE.test(to)) return res.status(400).json({ error: 'ongeldig ontvangeradres' });
  if (!body.trim()) return res.status(400).json({ error: 'leeg bericht' });

  const me = await db.query(
    `SELECT LOWER(mb.localpart) || '@' || LOWER(d.domain) AS address
       FROM mail_mailboxes mb JOIN mail_domains d ON d.id=mb.domain_id WHERE mb.id=$1`,
    [mailboxId]
  );
  const from = me.rows[0].address;

  const html = `<div style="font-family:Arial,sans-serif;white-space:pre-wrap;line-height:1.5">${escapeHtml(body)}</div>`;

  // Eerst proberen (interne adressen worden direct lokaal bezorgd), dan opslaan als verzonden.
  const relay = await sendMail(to, subject || '(geen onderwerp)', html, body);

  const saved = await db.query(
    `INSERT INTO mail_messages (mailbox_id, dir, from_addr, to_addr, subject, body_text, body_html)
     VALUES ($1,'out',$2,$3,$4,$5,$6) RETURNING id`,
    [mailboxId, from, to, subject || '(geen onderwerp)', body, html]
  );

  res.json({
    ok: true,
    id: saved.rows[0].id,
    local: !!relay.local,
    sent: !!relay.sent,
    relay: !!relay.sent && !relay.local,
    reason: relay.sent ? null : relay.reason || null,
  });
});

// ---------------- webhook (relay -> onze mailboxen) ----------------

router.post('/webhook', async (req, res) => {
  try {
    const token = await webhookToken();
    const given =
      req.get('x-mail-token') || req.body?.token || req.query?.token || '';
    if (String(given) !== token) return res.status(401).json({ error: 'onjuiste_token' });

    const tos = Array.isArray(req.body?.to) ? req.body.to : [req.body?.to];
    const clean = tos
      .map((t) => String(t || '').trim())
      .filter((t) => ADDR_RE.test(t))
      .slice(0, 20);
    if (!clean.length) return res.status(400).json({ error: 'geen geldige ontvangers' });

    const msg = {
      from: String(req.body?.from || '').slice(0, 254),
      subject: String(req.body?.subject || '').slice(0, 900),
      text: String(req.body?.text || req.body?.body || '').slice(0, 200000),
      html: String(req.body?.html || '').slice(0, 400000),
      code: req.body?.code || null,
      externalId: req.body?.id ? `wh:${String(req.body.id).slice(0, 120)}` : null,
    };
    if (!msg.code) {
      const { extractCode } = require('../smtp');
      msg.code = extractCode(msg.text || msg.html);
    }

    let delivered = 0;
    const missed = [];
    for (const t of clean) {
      const id = await deliverLocal(t, msg);
      if (id) delivered++;
      else missed.push(t);
    }
    res.json({ ok: true, accepted: clean.length, delivered, missed });
  } catch (e) {
    res.status(500).json({ error: 'webhook_mislukt', detail: e.message });
  }
});

module.exports = router;
