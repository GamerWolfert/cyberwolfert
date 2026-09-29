// Auth: eigen CyberWolfert-accounts (bcrypt + JWT) + Google-voorbereiding.
// Elke request met "Authorization: Bearer <token>" wordt aan die gebruiker gekoppeld;
// zonder token val je terug op de gedeelde 'wolfert'-gebruiker (gastmodus).
const jwt = require('jsonwebtoken');
const db = require('./db');

const JWT_SECRET = process.env.JWT_SECRET || 'cyberwolfert-dev-secret-VERANDER-DIT';
const JWT_DAYS = Number(process.env.JWT_DAYS || 30);

function signToken(userId) {
  return jwt.sign({ uid: userId }, JWT_SECRET, { expiresIn: `${JWT_DAYS}d` });
}

function readToken(req) {
  const h = req.headers.authorization || '';
  const m = h.match(/^Bearer\s+(.+)$/i);
  return m ? m[1] : null;
}

async function userIdFromToken(token) {
  try {
    const p = jwt.verify(token, JWT_SECRET);
    const uid = Number(p.uid) || null;
    if (!uid) return null;
    // Uitgelogd/gerapporteerd na uitgifte? Dan ongeldig (permanent, DB-check).
    try {
      const r = await db.query(
        'SELECT 1 FROM revoked_tokens WHERE user_id=$1 AND revoked_before > to_timestamp($2)',
        [uid, p.iat || 0]
      );
      if (r.rows.length) return null;
    } catch (_) {}
    return uid;
  } catch {
    return null;
  }
}

async function authOptional(req, res, next) {
  const t = readToken(req);
  req.userId = t ? await userIdFromToken(t) : null;
  if (req.userId) touchPresence(req.userId);
  next();
}

// --- Aanwezigheid (online-stip bij vrienden) ---
// Niet elke request wegschrijven: hoogstens 1x per 30s per gebruiker.
const ONLINE_WINDOW = 60; // seconden: "online" als je dit recent actief was
const seenAt = new Map();

function touchPresence(uid) {
  const now = Date.now();
  const last = seenAt.get(uid) || 0;
  if (now - last < 30000) return;
  seenAt.set(uid, now);
  db.query('UPDATE users SET last_seen=NOW() WHERE id=$1', [uid]).catch(() => {});
}

// Groeit anders eindeloos: ruim oude entries op.
const prune = setInterval(() => {
  const cutoff = Date.now() - 120000;
  for (const [uid, ts] of seenAt) if (ts < cutoff) seenAt.delete(uid);
}, 60000);
if (prune.unref) prune.unref();

async function authRequired(req, res, next) {
  const t = readToken(req);
  const uid = t ? await userIdFromToken(t) : null;
  if (!uid) return res.status(401).json({ error: 'login_required' });
  req.userId = uid;
  touchPresence(uid);
  next();
}

async function effectiveUserId(req) {
  if (req.userId) return req.userId;
  try {
    const r = await db.query('SELECT id FROM users WHERE username=$1', ['wolfert']);
    if (r.rows.length) return r.rows[0].id;
    const ins = await db.query(
      "INSERT INTO users (username, display_name) VALUES ('wolfert','Gast') RETURNING id"
    );
    return ins.rows[0].id;
  } catch {
    return null;
  }
}

module.exports = { signToken, authOptional, authRequired, effectiveUserId };
