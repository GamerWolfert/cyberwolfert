// Settings routes: achtergrond / thema per gebruiker in PostgreSQL.
const express = require('express');
const db = require('../db');
const { effectiveUserId } = require('../auth');
const router = express.Router();

async function getUserId(req) {
  const uid = await effectiveUserId(req);
  if (uid) return uid;
  const r = await db.query('SELECT id FROM users WHERE username=$1', ['wolfert']);
  if (r.rows.length) return r.rows[0].id;
  const ins = await db.query('INSERT INTO users (username) VALUES ($1) RETURNING id', ['wolfert']);
  return ins.rows[0].id;
}

router.get('/', async (req, res) => {
  try {
    const uid = await getUserId(req);
    const r = await db.query('SELECT * FROM user_settings WHERE user_id=$1', [uid]);
    res.json(r.rows[0] || {});
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'settings_load_failed' });
  }
});

router.post('/', async (req, res) => {
  try {
    const uid = await getUserId(req);
    const { theme, background_type, background_value, accent_color } = req.body;
    await db.query(
      `INSERT INTO user_settings (user_id, theme, background_type, background_value, accent_color, updated_at)
       VALUES ($1,$2,$3,$4,$5,NOW())
       ON CONFLICT (user_id) DO UPDATE SET
         theme=COALESCE(EXCLUDED.theme, user_settings.theme),
         background_type=COALESCE(EXCLUDED.background_type, user_settings.background_type),
         background_value=COALESCE(EXCLUDED.background_value, user_settings.background_value),
         accent_color=COALESCE(EXCLUDED.accent_color, user_settings.accent_color),
         updated_at=NOW()`,
      [uid, theme || null, background_type || null, background_value || null, accent_color || null]
    );
    const r = await db.query('SELECT * FROM user_settings WHERE user_id=$1', [uid]);
    res.json(r.rows[0]);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'settings_save_failed' });
  }
});

router.get('/backgrounds', async (req, res) => {
  const uid = await getUserId(req);
  const r = await db.query('SELECT * FROM backgrounds WHERE user_id=$1 ORDER BY created_at DESC', [uid]);
  res.json(r.rows);
});

router.post('/backgrounds', async (req, res) => {
  try {
    const uid = await getUserId(req);
    const { name, type, value, is_active } = req.body;
    if (!name || !type || !value) return res.status(400).json({ error: 'missing_fields' });
    if (is_active) await db.query('UPDATE backgrounds SET is_active=false WHERE user_id=$1', [uid]);
    const r = await db.query(
      'INSERT INTO backgrounds (user_id,name,type,value,is_active) VALUES ($1,$2,$3,$4,$5) RETURNING *',
      [uid, name, type, value, !!is_active]
    );
    if (is_active) {
      await db.query(
        'UPDATE user_settings SET background_type=$2, background_value=$3, updated_at=NOW() WHERE user_id=$1',
        [uid, type, value]
      );
    }
    res.json(r.rows[0]);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'background_save_failed' });
  }
});

module.exports = router;
