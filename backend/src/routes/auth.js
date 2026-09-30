// Account-routes: eigen AeroSurf-account + Google-login.
// - Registreren vereist gebruikersnaam + e-mail + wachtwoord; welkomstmail met
//   bevestigingslink + "dit was ik niet"-link (logout overal + apparaat-ban).
// - Inloggen met gebruikersnaam OF e-mailadres + wachtwoord (+ optioneel apparaat).
// - "Onthoud mij" aan = 365 dagen token, uit = 7 dagen.
// - Verbannen apparaten worden geweigerd met melding + unban-via-mail optie.
const express = require('express');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const db = require('../db');
const { log } = require('../discord');
const { mails, baseUrl } = require('../mail');
const { signToken, authRequired } = require('../auth');
const router = express.Router();

const USER_RE = /^[a-zA-Z0-9_. -]{3,32}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

function publicUser(row) {
  return {
    id: row.id,
    username: row.username,
    displayName: row.display_name || row.username,
    avatar: row.avatar_url || null,
    email: row.email || null,
    emailVerified: !!row.email_verified,
    is_admin: !!row.is_admin,
    provider: row.google_id ? 'google' : 'cyberwolfert',
  };
}

async function authEvent(userId, username, kind) {
  try {
    await db.query(
      'INSERT INTO auth_events (user_id, username, kind) VALUES ($1,$2,$3)',
      [userId, username, kind]
    );
  } catch (_) {}
}

function tokenFor(userId, remember) {
  const days = remember ? 365 : 7;
  const jwt = require('jsonwebtoken');
  const secret = process.env.JWT_SECRET || 'cyberwolfert-dev-secret-VERANDER-DIT';
  return jwt.sign({ uid: userId }, secret, { expiresIn: `${days}d` });
}

async function trackDevice(userId, deviceId, label) {
  if (!userId || !deviceId) return { banned: false };
  try {
    await db.query(
      `INSERT INTO devices (user_id, device_id, label, last_seen)
       VALUES ($1,$2,$3,NOW())
       ON CONFLICT (user_id, device_id) DO UPDATE SET last_seen=NOW(), label=COALESCE(EXCLUDED.label, devices.label)`,
      [userId, deviceId, label || 'Onbekend apparaat']
    );
    const r = await db.query('SELECT banned FROM devices WHERE user_id=$1 AND device_id=$2', [userId, deviceId]);
    return { banned: !!r.rows[0]?.banned };
  } catch {
    return { banned: false };
  }
}

router.get('/google-status', (req, res) => {
  res.json({ configured: !!process.env.GOOGLE_CLIENT_ID });
});

router.post('/register', async (req, res) => {
  const { username, password, displayName, email, deviceId, deviceLabel, remember } = req.body || {};
  if (!username || !USER_RE.test(username)) {
    return res.status(400).json({ error: 'ongeldige gebruikersnaam (3-32 tekens, letters/cijfers/._- )' });
  }
  if (!email || !EMAIL_RE.test(email)) {
    return res.status(400).json({ error: 'vul een geldig e-mailadres in' });
  }
  if (!password || String(password).length < 4) {
    return res.status(400).json({ error: 'wachtwoord te kort (min. 4 tekens)' });
  }
  try {
    const exists = await db.query(
      'SELECT id FROM users WHERE LOWER(username)=LOWER($1) OR LOWER(email)=LOWER($2)',
      [username, email]
    );
    if (exists.rows.length) return res.status(409).json({ error: 'gebruikersnaam of e-mail bestaat al' });
    const hash = await bcrypt.hash(String(password), 10);
    const emailToken = crypto.randomBytes(24).toString('hex');
    const r = await db.query(
      'INSERT INTO users (username, password_hash, display_name, email, email_token) VALUES ($1,$2,$3,$4,$5) RETURNING *',
      [username, hash, displayName || username, email, emailToken]
    );
    const user = publicUser(r.rows[0]);
    const base = baseUrl(req);
    const verifyUrl = `${base}/api/auth/verify?token=${emailToken}`;
    const reportUrl = `${base}/api/auth/report?token=${emailToken}`;
    await mails.accountAangemaakt(email, user.displayName, verifyUrl, reportUrl);
    await trackDevice(user.id, deviceId, deviceLabel);
    log.login(user.username, 'cyberwolfert-register');
    authEvent(user.id, user.username, 'register');
    res.json({ token: tokenFor(user.id, remember), user });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'register_failed' });
  }
});

// E-mail bevestigen (link uit welkomstmail)
router.get('/verify', async (req, res) => {
  try {
    const r = await db.query('SELECT * FROM users WHERE email_token=$1', [req.query.token || '']);
    if (!r.rows.length) return res.status(400).send('<h1>Ongeldige of verlopen link.</h1>');
    await db.query('UPDATE users SET email_verified=true, email_token=NULL WHERE id=$1', [r.rows[0].id]);
    res.send('<h1 style="font-family:sans-serif">🚀 E-mailadres bevestigd! Je kunt nu inloggen in AeroSurf.</h1>');
  } catch (e) {
    res.status(500).send('<h1>Er ging iets mis.</h1>');
  }
});

// "Dit was ik niet": alles uitloggen + apparaat verbannen + mail met unban-link
router.get('/report', async (req, res) => {
  try {
    const r = await db.query('SELECT * FROM users WHERE email_token=$1', [req.query.token || '']);
    if (!r.rows.length) return res.status(400).send('<h1>Ongeldige of verlopen link.</h1>');
    const user = r.rows[0];
    await db.query('INSERT INTO revoked_tokens (user_id) VALUES ($1)', [user.id]);
    const banToken = crypto.randomBytes(24).toString('hex');
    await db.query('UPDATE users SET email_token=$1 WHERE id=$2', [`unban:${banToken}`, user.id]);
    if (deviceIdOf(req)) {
      await db.query(
        `INSERT INTO devices (user_id, device_id, banned) VALUES ($1,$2,true)
         ON CONFLICT (user_id, device_id) DO UPDATE SET banned=true`,
        [user.id, deviceIdOf(req)]
      );
    } else {
      await db.query('UPDATE devices SET banned=true WHERE user_id=$1', [user.id]);
    }
    const unbanUrl = `${baseUrl(req)}/api/auth/unban?token=${banToken}`;
    await mails.apparaatVerbannen(user.email, user.display_name || user.username, unbanUrl);
    res.send('<h1 style="font-family:sans-serif">🛡️ Account beveiligd: overal uitgelogd en apparaat verbannen. Check je e-mail om te deblokkeren.</h1>');
  } catch (e) {
    console.error(e);
    res.status(500).send('<h1>Er ging iets mis.</h1>');
  }
});

function deviceIdOf(req) {
  return (req.headers['x-device-id'] || req.body?.deviceId || '').toString().slice(0, 128) || null;
}

// Apparaat deblokkeren via e-mail-link
router.get('/unban', async (req, res) => {
  try {
    const r = await db.query('SELECT * FROM users WHERE email_token=$1', [`unban:${req.query.token || ''}`]);
    if (!r.rows.length) return res.status(400).send('<h1>Ongeldige of verlopen link.</h1>');
    const user = r.rows[0];
    await db.query('UPDATE devices SET banned=false WHERE user_id=$1', [user.id]);
    await db.query('UPDATE users SET email_token=NULL WHERE id=$1', [user.id]);
    await mails.apparaatGedeblokkeerd(user.email, user.display_name || user.username);
    res.send('<h1 style="font-family:sans-serif">🚀 Apparaat gedeblokkeerd. Je kunt weer inloggen.</h1>');
  } catch (e) {
    res.status(500).send('<h1>Er ging iets mis.</h1>');
  }
});

router.post('/login', async (req, res) => {
  const { username, password, remember, deviceId, deviceLabel } = req.body || {};
  if (!username || !password) return res.status(400).json({ error: 'missing_fields' });
  try {
    const r = await db.query(
      'SELECT * FROM users WHERE LOWER(username)=LOWER($1) OR LOWER(email)=LOWER($1)',
      [username]
    );
    const row = r.rows[0];
    if (!row || !row.password_hash) return res.status(401).json({ error: 'onbekende combinatie' });
    const ok = await bcrypt.compare(String(password), row.password_hash);
    if (!ok) return res.status(401).json({ error: 'onbekende combinatie' });
    const dev = await trackDevice(row.id, deviceId || deviceIdOf(req), deviceLabel);
    if (dev.banned) {
      return res.status(403).json({
        error: 'apparaat verbannen',
        detail: 'Dit apparaat is verbannen. Deblokkeer het via de link in je e-mail.',
      });
    }
    const user = publicUser(row);
    log.login(user.username, 'cyberwolfert-login');
    authEvent(user.id, user.username, 'login');
    res.json({ token: tokenFor(user.id, remember), user });
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

// Uitloggen op dit apparaat (token intrekken voor dit moment)
router.post('/logout', authRequired, async (req, res) => {
  try {
    await db.query('INSERT INTO revoked_tokens (user_id) VALUES ($1)', [req.userId]);
    res.json({ ok: true });
  } catch (e) {
    res.json({ ok: true });
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
          'INSERT INTO users (username, google_id, display_name, avatar_url, email, email_verified) VALUES ($1,$2,$3,$4,$5,true) RETURNING *',
          [name.slice(0, 32), gid, name, info.picture || null, info.email || null]
        );
      }
    }
    const user = publicUser(r.rows[0]);
    log.login(user.username, 'google');
    res.json({ token: tokenFor(user.id, req.body?.remember), user });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'google_failed' });
  }
});

module.exports = router;
