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
    return Number(p.uid) || null;
  } catch {
    return null;
  }
}

async function authOptional(req, res, next) {
  const t = readToken(req);
  req.userId = t ? await userIdFromToken(t) : null;
  next();
}

async function authRequired(req, res, next) {
  const t = readToken(req);
  const uid = t ? await userIdFromToken(t) : null;
  if (!uid) return res.status(401).json({ error: 'login_required' });
  req.userId = uid;
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
