// Account-routes: eigen CyberWolfert-account + Google-login (code klaar).
//   POST /api/auth/register { username, password, displayName? }
//   POST /api/auth/login    { username, password }  -> { token, user }
//   GET  /api/auth/me (Bearer) -> { user }
// Google: zet GOOGLE_CLIENT_ID in config.env (zie README).
const express = require('express');
const bcrypt = require('bcryptjs');
const db = require('../db');
const { log } = require('../discord');
const { signToken, authRequired } = require('../auth');
const router = express.Router();

const USER_RE = /^[a-zA-Z0-9_. -]{3,32}$/;

function publicUser(row) {
  return {
    id: row.id,
    username: row.username,
    displayName: row.display_name || row.username,
    avatar: row.avatar_url || null,
    provider: row.google_id ? 'google' : 'cyberwolfert',
  };
}

router.get('/google-status', (req, res) => {
  res.json({ configured: !!process.env.GOOGLE_CLIENT_ID });
});

router.post('/register', async (req, res) => {
  const { username, password, displayName } = req.body || {};
  if (!username || !USER_RE.test(username)) {
    return res.status(400).json({ error: 'ongeldige gebruikersnaam (3-32 tekens, letters/cijfers/._- )' });
  }
  if (!password || String(password).length < 4) {
    return res.status(400).json({ error: 'wachtwoord te kort (min. 4 tekens)' });
  }
  try {
    const exists = await db.query('SELECT id FROM users WHERE LOWER(username)=LOWER($1)', [username]);
    if (exists.rows.length) return res.status(409).json({ error: 'gebruikersnaam bestaat al' });
    const hash = await bcrypt.hash(String(password), 10);
    const r = await db.query(
      'INSERT INTO users (username, password_hash, display_name) VALUES ($1,$2,$3) RETURNING *',
      [username, hash, displayName || username]
    );
    const user = publicUser(r.rows[0]);
    log.login(user.username, 'cyberwolfert-register');
    res.json({ token: signToken(user.id), user });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'register_failed' });
  }
});

router.post('/login', async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ error: 'missing_fields' });
  try {
    const r = await db.query('SELECT * FROM users WHERE LOWER(username)=LOWER($1)', [username]);
    const row = r.rows[0];
    if (!row || !row.password_hash) return res.status(401).json({ error: 'onbekende combinatie' });
    const ok = await bcrypt.compare(String(password), row.password_hash);
    if (!ok) return res.status(401).json({ error: 'onbekende combinatie' });
    const user = publicUser(row);
    log.login(user.username, 'cyberwolfert-login');
    res.json({ token: signToken(user.id), user });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'login_failed' });
  }
});

router.get('/me', authRequired, async (req, res) => {
  try {
    const r = await db.query('SELECT * FROM users WHERE id=$1', [req.userId]);
    if (!r.rows.length) return res.status(404).json({ error: 'not_found' });
    res.json({ user: publicUser(r.rows[0]) });
  } catch (e) {
    res.status(500).json({ error: 'me_failed' });
  }
});

router.post('/google', async (req, res) => {
  if (!process.env.GOOGLE_CLIENT_ID) {
    return res.status(501).json({ error: 'google_niet_ingesteld' });
  }
  const { id_token } = req.body || {};
  if (!id_token) return res.status(400).json({ error: 'missing_id_token' });
  try {
    const vr = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(id_token)}`
    );
    if (!vr.ok) return res.status(401).json({ error: 'google_token_ongeldig' });
    const info = await vr.json();
    if (info.aud !== process.env.GOOGLE_CLIENT_ID) {
      return res.status(401).json({ error: 'google_token_voor_andere_app' });
    }
    const gid = info.sub;
    const email = info.email || `google_${gid}@example.invalid`;
    const name = info.name || email.split('@')[0];
    let r = await db.query('SELECT * FROM users WHERE google_id=$1', [gid]);
    if (!r.rows.length) {
      const same = await db.query('SELECT * FROM users WHERE LOWER(username)=LOWER($1)', [name]);
      if (same.rows.length && !same.rows[0].google_id) {
        r = await db.query(
          'UPDATE users SET google_id=$1, avatar_url=$2, display_name=COALESCE(display_name,$3) WHERE id=$4 RETURNING *',
          [gid, info.picture || null, name, same.rows[0].id]
        );
      } else {
        r = await db.query(
          'INSERT INTO users (username, google_id, display_name, avatar_url) VALUES ($1,$2,$3,$4) RETURNING *',
          [name.slice(0, 32), gid, name, info.picture || null]
        );
      }
    }
    const user = publicUser(r.rows[0]);
    log.login(user.username, 'google');
    res.json({ token: signToken(user.id), user });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'google_failed' });
  }
});

module.exports = router;
