// Entry-point backend Mini-PC. Tunnel-ready: trust proxy, CORS-allowlist,
// rate-limit op /api, uploads + Flutter-web hosting + Discord presence.
// Config: backend/config.env (kopie van .env.example).
require('dotenv').config({ path: require('path').join(__dirname, '..', 'config.env') });
const path = require('path');
const fs = require('fs');
const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const multer = require('multer');
const settingsRouter = require('./routes/settings');
const searchRouter = require('./routes/search');
const aiRouter = require('./routes/ai');
const systemRouter = require('./routes/system');
const proxyRouter = require('./routes/proxy');
const authRouter = require('./routes/auth');
const wolfsynRouter = require('./routes/wolfsyn');
const adminRouter = require('./routes/admin');
const agentRouter = require('./routes/agent');
const mailRouter = require('./routes/mail');
const gifsRouter = require('./routes/gifs');
const { authOptional } = require('./auth');
const { pool } = require('./db');
const { startSmtp } = require('./smtp');

const app = express();
app.set('trust proxy', 1);

const allowList = (process.env.CORS_ORIGINS || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
app.use(
  cors({
    origin: (origin, cb) => {
      if (!origin || allowList.length === 0 || allowList.includes(origin)) return cb(null, true);
      return cb(new Error('CORS blocked: ' + origin));
    },
  })
);
app.use(express.json({ limit: '2mb' }));

app.use(
  '/api/',
  rateLimit({ windowMs: 60 * 1000, max: 120, standardHeaders: true, legacyHeaders: false })
);

const uploadDir = path.join(__dirname, '..', process.env.UPLOAD_DIR || 'uploads');
fs.mkdirSync(uploadDir, { recursive: true });
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => {
    const safe = Date.now() + '-' + String(file.originalname || 'bg').replace(/[^a-zA-Z0-9._-]/g, '_');
    cb(null, safe);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: Number(process.env.MAX_UPLOAD_MB || 8) * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (/^image\//.test(file.mimetype)) return cb(null, true);
    cb(new Error('Alleen afbeeldingen toegestaan'));
  },
});
app.use('/uploads', express.static(uploadDir));

function publicBase(req) {
  if (process.env.PUBLIC_URL) return String(process.env.PUBLIC_URL).replace(/\/$/, '');
  return `${req.protocol}://${req.get('host')}`;
}

app.post('/api/uploads', upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'missing_file' });
  res.json({ url: `${publicBase(req)}/uploads/${req.file.filename}` });
});

app.get('/api/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true, service: 'cyberwolfert-backend', db: 'up', publicUrl: process.env.PUBLIC_URL || null });
  } catch (e) {
    res.status(500).json({ ok: false, db: 'down', detail: e.message });
  }
});
app.use('/api/auth', authRouter);
app.use('/api/wolf', wolfsynRouter);
app.use('/api/admin', adminRouter);
app.use('/api/mail', mailRouter);
app.use('/api/gifs', gifsRouter);
app.use('/api', authOptional);
app.use('/api/settings', settingsRouter);
app.use('/api/search', searchRouter);
app.use('/api/ai', aiRouter);
app.use('/api/ai/agent', agentRouter);
app.use('/api', systemRouter);
app.use('/api', proxyRouter);

const downloadDir = path.join(__dirname, '..', 'downloads');
fs.mkdirSync(downloadDir, { recursive: true });
app.use('/downloads', express.static(downloadDir));

const webDir = path.join(__dirname, '..', 'public');
if (fs.existsSync(webDir)) {
  app.use(express.static(webDir));
  app.get(/^\/(?!api|uploads|downloads).*/, (req, res, next) => {
    if (req.method !== 'GET' || req.path.includes('.')) return next();
    res.sendFile(path.join(webDir, 'index.html'));
  });
  console.log('[AeroSurf] host Flutter-web uit ./public (via internet te openen via tunnel)');
}

app.use((err, req, res, next) => {
  console.error('[api]', err.message);
  res.status(400).json({ error: 'bad_request', detail: err.message });
});

// Express 4 vangt asynchrone fouten in routes niet -> nooit de hele
// backend laten crashen op één mislukte query.
process.on('unhandledRejection', (err) => {
  console.error('[net] niet-afgehandelde belofte:', (err && (err.stack || err.message)) || err);
});
process.on('uncaughtException', (err) => {
  console.error('[net] onverwachte fout:', (err && (err.stack || err.message)) || err);
});

const PORT = Number(process.env.PORT || 43711);
const HOST = process.env.HOST || '0.0.0.0';

// Discord 24/7 presence (inline): LOGS-SERVER online zolang backend draait
function startPresence() {
  const token = process.env.DISCORD_BOT_TOKEN;
  const WS = typeof globalThis.WebSocket !== 'undefined' ? globalThis.WebSocket : null;
  if (!token || !WS) {
    console.log('[presence] uit (geen token of WebSocket)');
    return;
  }
  let hb = null;
  let seq = null;
  const link = () => {
    const ws = new WS('wss://gateway.discord.gg/?v=10&encoding=json');
    ws.onopen = () => console.log('[presence] gateway verbonden');
    ws.onmessage = (ev) => {
      let p;
      try {
        p = JSON.parse(ev.data);
      } catch {
        return;
      }
      if (p.s) seq = p.s;
      if (p.op === 10) {
        clearInterval(hb);
        hb = setInterval(() => {
          if (ws.readyState === 1) ws.send(JSON.stringify({ op: 1, d: seq }));
        }, p.d.heartbeat_interval);
        ws.send(JSON.stringify({
          op: 2,
          d: {
            token,
            intents: 0,
            properties: { os: 'linux', browser: 'cyberwolfert', device: 'cyberwolfert' },
            presence: { status: 'online', activities: [{ name: 'AeroSurf logs', type: 3 }], afk: false },
          },
        }));
        console.log('[presence] online');
      } else if (p.op === 7 || p.op === 9) {
        try {
          ws.close();
        } catch (_) {}
      }
    };
    ws.onclose = () => {
      clearInterval(hb);
      setTimeout(link, 8000);
    };
    ws.onerror = () => {
      try {
        ws.close();
      } catch (_) {}
    };
  };
  link();
}

app.listen(PORT, HOST, () => {
  console.log(`[AeroSurf] backend live op http://${HOST}:${PORT}`);
  if (process.env.PUBLIC_URL) console.log(`[AeroSurf] publiek via tunnel: ${process.env.PUBLIC_URL}`);
  startPresence();
  startSmtp();
  const { send, CHANNELS } = require('./discord');
  send(CHANNELS.minipcSysteem, `Backend (her)start op poort ${PORT} — ${new Date().toISOString().slice(0, 19)}Z`);
});
