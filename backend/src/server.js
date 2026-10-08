// Entry-point backend Mini-PC. Tunnel-ready: trust proxy, CORS-allowlist,
// rate-limit op /api, uploads + Flutter-web hosting + Discord presence.
// Config: backend/config.env (kopie van .env.example).
require('dotenv').config({ path: require('path').join(__dirname, '..', 'config.env') });
const http = require('http');
const path = require('path');
const fs = require('fs');
const express = require('express');
const cors = require('cors');
const compression = require('compression');
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
const { startCalls } = require('./calls');

const app = express();
app.set('trust proxy', 1);

// Gzip/Brotli voor alles wat tekst is: Flutter-web (main.dart.js, canvaskit)
// en JSON-antwoorden worden zo 5-10x kleiner via de tunnel.
app.use(compression());

// Basis security-headers (helmet-achtig, zonder extra dependency).
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'SAMEORIGIN');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader(
    'Permissions-Policy',
    'camera=(self), microphone=(self), geolocation=(), payment=(), usb=()'
  );
  next();
});

// Traag/fout logging: alleen signaleren als het ertoe doet (niet elke poll).
const REQUESTS = { total: 0, errors: 0, slow: 0 };
app.use((req, res, next) => {
  const t0 = Date.now();
  REQUESTS.total += 1;
  res.on('finish', () => {
    const ms = Date.now() - t0;
    if (res.statusCode >= 500) REQUESTS.errors += 1;
    if (ms > 3000 || res.statusCode >= 500) {
      REQUESTS.slow += 1;
      console.warn(`[traag] ${req.method} ${req.path} -> ${res.statusCode} in ${ms}ms`);
    }
  });
  next();
});

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

// Rate-limit in twee buckets: algemeen ruim (app-polls, AI, WS-upgrades),
// auth streng zodat wachtwoord-gokken duur wordt.
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: Number(process.env.RATE_MAX || 300),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'too_many_requests' },
});
const authLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: Number(process.env.RATE_AUTH_MAX || 20),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'too_many_requests' },
});
app.use('/api/auth', authLimiter);
app.use('/api/', apiLimiter);

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
app.use('/uploads', express.static(uploadDir, { maxAge: '7d', immutable: true }));

// Logo/afbeeldingen voor officiele e-mails (mailtemplates verwijzen hiernaartoe).
app.use(
  '/assets',
  express.static(path.join(__dirname, '..', 'assets'), { maxAge: '1d' })
);

function publicBase(req) {
  if (process.env.PUBLIC_URL) return String(process.env.PUBLIC_URL).replace(/\/$/, '');
  return `${req.protocol}://${req.get('host')}`;
}

app.post('/api/uploads', upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'missing_file' });
  res.json({ url: `${publicBase(req)}/uploads/${req.file.filename}` });
});

function diskInfo() {
  try {
    const s = fs.statfsSync('/');
    const total = s.blocks * s.bsize;
    const free = s.bavail * s.bsize;
    return {
      usedPct: Math.round(((total - free) / total) * 100),
      freeGb: Math.round(free / 1e9),
      totalGb: Math.round(total / 1e9),
    };
  } catch (_) {
    return null;
  }
}

async function ollamaOk() {
  // OLLAMA_URL wijst op de chat-endpoint (/api/chat) -> base URL afleiden.
  const base = String(process.env.OLLAMA_URL || 'http://127.0.0.1:11434/api/chat').replace(
    /\/api\/.*$/,
    ''
  );
  try {
    const ctl = new AbortController();
    const to = setTimeout(() => ctl.abort(), 1500);
    const r = await fetch(`${base}/api/version`, { signal: ctl.signal });
    clearTimeout(to);
    const j = await r.json();
    return { up: true, version: j.version || '?' };
  } catch (_) {
    return { up: false, version: null };
  }
}

app.get('/api/health', async (req, res) => {
  const mem = process.memoryUsage();
  try {
    await pool.query('SELECT 1');
    res.json({
      ok: true,
      service: 'cyberwolfert-backend',
      db: 'up',
      publicUrl: process.env.PUBLIC_URL || null,
      uptimeSec: Math.round(process.uptime()),
      disk: diskInfo(),
      ollama: await ollamaOk(),
      requests: REQUESTS,
      rssMb: Math.round(mem.rss / 1048576),
    });
  } catch (e) {
    res.status(500).json({ ok: false, db: 'down', detail: e.message, disk: diskInfo() });
  }
});
// Wordt altijd JSON (de SPA-fallback hieronder zou er anders index.html voor
// teruggeven) — de app gebruikt /version als "is deze backend alive?"-proef.
app.get('/version', (req, res) => {
  let v = { app: 'AeroSurf Browser', version: '?', build: '?' };
  try {
    v = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'version.json'), 'utf8'));
  } catch (_) {}
  res.json({ ok: true, service: 'cyberwolfert-backend', ...v });
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
  app.use(
    express.static(webDir, {
      etag: true,
      lastModified: true,
      setHeaders: (res, filePath) => {
        if (filePath.endsWith('index.html') || filePath.endsWith('tunnel.txt')) {
          res.setHeader('Cache-Control', 'no-cache');
        } else if (/\.(js|css|woff2?|ttf|png|jpe?g|svg|webp|ico|wasm|map)$/i.test(filePath)) {
          // Flutter-web assets zijn niet gehasht -> kort cachen, wel gecomprimeerd.
          res.setHeader('Cache-Control', 'public, max-age=3600');
        }
      },
    })
  );
  app.get(/^\/(?!api|uploads|downloads).*/, (req, res, next) => {
    if (req.method !== 'GET' || req.path.includes('.')) return next();
    res.sendFile(path.join(webDir, 'index.html'));
  });
  console.log('[AeroSurf] host Flutter-web uit ./public (via internet te openen via tunnel)');
}

// JSON-404 voor API-paden (in plaats van verpakte HTML-foutpagina).
app.use('/api', (req, res) => {
  res.status(404).json({ error: 'not_found', path: req.originalUrl });
});

// Foutafhandeling: behoud het bekende 400-antwoord dat de app verwacht, maar
// geef 500 pas écht als het onze schuld is en log het stacktrace één keer.
app.use((err, req, res, next) => {
  const status = Number(err.status || err.statusCode) || (err.type === 'entity.too.large' ? 413 : 400);
  console.error('[api]', status, err.message);
  if (status >= 500) console.error('[api]', err.stack);
  res.status(status).json({ error: status >= 500 ? 'server_error' : 'bad_request', detail: err.message });
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

const server = http.createServer(app);
server.listen(PORT, HOST, () => {
  console.log(`[AeroSurf] backend live op http://${HOST}:${PORT}`);
  if (process.env.PUBLIC_URL) console.log(`[AeroSurf] publiek via tunnel: ${process.env.PUBLIC_URL}`);
  startCalls(server);
  startPresence();
  startSmtp();
  const { startUrlWatch } = require('./url_watch');
  startUrlWatch();
  const { startDiskWatch } = require('./disk_watch');
  startDiskWatch();
  const { send, CHANNELS } = require('./discord');
  send(CHANNELS.minipcSysteem, `Backend (her)start op poort ${PORT} — ${new Date().toISOString().slice(0, 19)}Z`);
});
