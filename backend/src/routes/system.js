// Systeem-routes: versie/update-check + downloads + universele log-API.
const express = require('express');
const path = require('path');
const fs = require('fs');
const { send, CHANNELS } = require('../discord');
const router = express.Router();

function loadVersion() {
  try {
    return JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'version.json'), 'utf8'));
  } catch {
    return { app: 'CyberWolfert Browser', version: '0.0.0', build: 0 };
  }
}

function downloadDir() {
  const d = path.join(__dirname, '..', '..', 'downloads');
  fs.mkdirSync(d, { recursive: true });
  return d;
}

function publicBase(req) {
  if (process.env.PUBLIC_URL) return String(process.env.PUBLIC_URL).replace(/\/$/, '');
  return `${req.protocol}://${req.get('host')}`;
}

router.get('/version', (req, res) => {
  const v = loadVersion();
  const base = publicBase(req);
  const dir = downloadDir();
  const has = (f) => fs.existsSync(path.join(dir, f));
  res.json({
    ...v,
    downloads: {
      apk: has('CyberWolfert.apk') ? `${base}/downloads/CyberWolfert.apk` : null,
      windows: has('CyberWolfert-Windows.zip') ? `${base}/downloads/CyberWolfert-Windows.zip` : null,
      ios: v.iosUrl || null,
      bundle: has('CyberWolfert-apps.zip') ? `${base}/downloads/CyberWolfert-apps.zip` : null,
    },
  });
});

router.get('/update-check', (req, res) => {
  const v = loadVersion();
  const build = Number(req.query.build || 0);
  res.json({
    current: { version: v.version, build: v.build, notes: v.notes },
    updateAvailable: build < Number(v.build || 0),
    forceUpdate: false,
  });
});

// POST /api/logs { secret, channel, text } -> direct een Discord-kanaal in.
router.post('/logs', async (req, res) => {
  const { secret, channel, text } = req.body || {};
  if (!process.env.LOG_SECRET || secret !== process.env.LOG_SECRET) {
    return res.status(403).json({ error: 'forbidden' });
  }
  const allowed = new Set(Object.values(CHANNELS).filter(Boolean));
  const id = CHANNELS[channel] || channel;
  if (!id || !allowed.has(String(id))) return res.status(400).json({ error: 'onbekend kanaal' });
  await send(String(id), String(text || '').slice(0, 1900));
  res.json({ ok: true });
});

module.exports = router;
