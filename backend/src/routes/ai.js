// CyberWolf AI: Ollama -> OpenAI-compat -> lokale slimme modus (met geheugen).
// Presenteert zich ALTIJD als "CyberWolf AI".
const express = require('express');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const db = require('../db');
const { log, naamOf } = require('../discord');
const { effectiveUserId } = require('../auth');
const { globalSearch } = require('./search');
const router = express.Router();

const IDENTITY =
  'Je bent CyberWolf AI, de vaste slimme assistent van de CyberWolfert Browser. ' +
  'Je hebt een eigen Mini-PC (Linux) met internet, PostgreSQL, Ollama en Discord-logging.';

const STYLE =
  'Regels voor elke reactie: ' +
  '1) Noem jezelf ALLEEN CyberWolf AI, nooit een andere modelnaam. ' +
  '2) Schrijf perfect, natuurlijk Nederlands: spreek de gebruiker aan met "je", nooit met "u". ' +
  '3) Schrijf ALTIJD in de eerste persoon (ik/mij/mijn), NOOIT in de derde persoon. ' +
  '4) Wees respectvol en hartelijk, zonder slijmerig te worden. ' +
  '5) Gewone antwoorden: maximaal 3 zinnen, kort en to-the-point, geen herhaling. ' +
  '6) Op een simpele groet antwoord je met exact één vrolijke zin, bv. "Hoi! Waar kan ik je mee helpen?" ' +
  '7) Wees eerlijk: weet je het niet zeker, zeg dat dan gewoon.';

const CODING =
  'Regels als je code schrijft: ' +
  '1) Je bent een uitstekende programmeur (Python, JavaScript/TypeScript, Dart/Flutter, HTML/CSS, SQL, Bash, C#). ' +
  '2) Geef ALTIJD complete, werkende code die meteen draait — nooit fragments of "..."-plaats houders. ' +
  '3) Zet code in een codeblok met de juiste taal, bv. ```python. ' +
  '4) Zet er kort bij hoe je het uitvoert (bestandsnaam + commando). ' +
  '5) Uitleg in max 5 korte zinnen, daarna de code. ' +
  '6) Gebruik veilige standaarden: geen expliciete wachtwoordsleutels in code.';

const KNOWN_MODELS = ['qwen2.5:1.5b', 'qwen2.5-coder:1.5b', 'qwen2.5-coder:3b', 'qwen2.5-coder:7b', 'qwen2.5-coder:14b'];

function fetchTimeout(url, opts = {}, ms = 25000) {
  const c = new AbortController();
  const t = setTimeout(() => c.abort(), ms);
  return fetch(url, { ...opts, signal: c.signal }).finally(() => clearTimeout(t));
}

function ollamaUrl() {
  const u = process.env.OLLAMA_URL || 'http://127.0.0.1:11434/api/chat';
  return /\/api\/chat$/.test(u) ? u : u.replace(/\/$/, '') + '/api/chat';
}

function isCodeAsk(m) {
  const s = m.toLowerCase();
  if (s.length > 400) return false;
  return /```/.test(m) ||
    /\b(script|code|coderen|programma|functie|klasse|class |function |def |const |let |var |import |export |html|css|javascript|typescript|python|dart|flutter|sql|bash|shell|powershell|regex|api|endpoint|compile|foutmelding|error|exception|stacktrace|debug|bug|refactor|widget|component)\b/.test(s) &&
    /\b(maak|schrijf|geef|bouw|fix|herstel|fout|foutje|uitleg|hoe|help|schrijf|cre[eë]er|toon|genereer|nodig|nodig hebt|script|code)\b/.test(s) ||
    /maak.*(script|code|programma|bestand)/.test(s);
}

function isLookupAsk(m) {
  const s = m.toLowerCase().trim();
  if (s.length > 160 || isCodeAsk(m)) return false;
  return /^(wat|wie|waar|wanneer|waarom|welke|welk|hoeveel|hoe laat|hoe duur|is |zijn |kan |mag )/.test(s) ||
    /\b(verschil tussen|uitleg van|leg uit|wat betekent|nieuws over|actueel|het weer|temperatuur)\b/.test(s);
}

async function ollamaChat(messages, codeMode) {
  const model = codeMode
    ? (process.env.AI_CODE_MODEL || 'qwen2.5-coder:3b')
    : (process.env.OLLAMA_MODEL || 'qwen2.5:1.5b');
  const opts = codeMode
    ? { num_predict: 1600, temperature: 0.15, top_p: 0.9, num_ctx: 4096, repeat_penalty: 1.05, keep_alive: '15m' }
    : { num_predict: 220, temperature: 0.3, top_p: 0.9, num_ctx: 2048, repeat_penalty: 1.1, keep_alive: '5m' };

  // Kleine modellen volgen de LAATSTE instructie het best: stijlregel achteraan.
  const styled = messages.map((mm) => ({ ...mm }));
  const last = styled[styled.length - 1];
  const tail = codeMode
    ? '[Regels: Nederlands met "je" (nooit "u"), eerste persoon (ik), complete werkende code in een codeblok met taal-tag, korte uitleg.]'
    : '[Regels: Nederlands met "je" (nooit "u"), eerste persoon (ik), kort en to-the-point, max 3 zinnen, geen aannames.]';
  styled[styled.length - 1] = { ...last, content: `${last.content}\n${tail}` };

  const r = await fetchTimeout(ollamaUrl(), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, messages: styled, stream: false, options: opts }),
  }, codeMode ? 120000 : 45000);
  if (!r.ok) throw new Error(`ollama http ${r.status}`);
  const j = await r.json();
  const reply = j.message?.content || j.response;
  if (!reply) throw new Error('ollama empty');
  return { reply, engine: `ollama:${model}` };
}

async function openaiCompatChat(messages) {
  if (!process.env.OPENAI_COMPAT_URL || !process.env.OPENAI_COMPAT_KEY) {
    throw new Error('no openai-compat configured');
  }
  const r = await fetchTimeout(`${process.env.OPENAI_COMPAT_URL}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${process.env.OPENAI_COMPAT_KEY}`,
    },
    body: JSON.stringify({ model: process.env.OPENAI_COMPAT_MODEL || 'gpt-4o-mini', messages }),
  }, 60000);
  if (!r.ok) throw new Error(`openai-compat http ${r.status}`);
  const j = await r.json();
  const reply = j.choices?.[0]?.message?.content;
  if (!reply) throw new Error('openai-compat empty');
  return { reply, engine: 'openai-compat' };
}

const uploadDir = path.join(__dirname, '..', '..', 'uploads');
try {
  fs.mkdirSync(uploadDir, { recursive: true });
} catch (_) {}
const uploadAi = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => cb(null, uploadDir),
    filename: (req, file, cb) => {
      const safe = `ai-${Date.now()}-` + String(file.originalname || 'img').replace(/[^a-zA-Z0-9._-]/g, '_');
      cb(null, safe);
    },
  }),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (/^image\//.test(file.mimetype)) return cb(null, true);
    cb(new Error('Alleen afbeeldingen'));
  },
});

async function ollamaVision(messages, imageB64) {
  const model = process.env.OLLAMA_VISION_MODEL || 'qwen2.5-vl:3b';
  const msgs = messages.map((mm) => ({ ...mm }));
  msgs[msgs.length - 1] = { ...msgs[msgs.length - 1], images: [imageB64] };
  const r = await fetchTimeout(ollamaUrl(), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, messages: msgs, stream: false, options: { num_predict: 400 } }),
  }, 90000);
  if (!r.ok) throw new Error(`vision http ${r.status}`);
  const j = await r.json();
  const reply = j.message?.content || j.response;
  if (!reply) throw new Error('vision empty');
  return { reply, engine: `ollama-vision:${model}` };
}

function versionInfo() {
  try {
    return JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'version.json'), 'utf8'));
  } catch {
    return { version: '?', build: '?' };
  }
}

function memoryFile() {
  return path.join(__dirname, '..', '..', 'ai_memory.json');
}
function readFileMemory() {
  try {
    return JSON.parse(fs.readFileSync(memoryFile(), 'utf8'));
  } catch {
    return {};
  }
}
async function getMemory(uid) {
  if (uid) {
    try {
      const r = await db.query('SELECT feit FROM ai_memory WHERE user_id=$1 ORDER BY id DESC LIMIT 20', [uid]);
      return r.rows.map((x) => x.feit);
    } catch (_) {}
  }
  return readFileMemory()[String(uid ?? 'gast')] || [];
}
async function saveMemory(uid, feit) {
  if (!feit) return;
  if (uid) {
    try {
      await db.query('INSERT INTO ai_memory (user_id, feit) VALUES ($1,$2)', [uid, feit]);
      return;
    } catch (_) {}
  }
  const all = readFileMemory();
  const k = String(uid ?? 'gast');
  all[k] = [...(all[k] || []), feit].slice(-20);
  try {
    fs.writeFileSync(memoryFile(), JSON.stringify(all, null, 2));
  } catch (_) {}
}
async function forgetMemory(uid, needle) {
  if (uid) {
    try {
      const r = await db.query('DELETE FROM ai_memory WHERE user_id=$1 AND feit ILIKE $2', [uid, `%${needle}%`]);
      if ((r.rowCount || 0) > 0) return r.rowCount;
    } catch (_) {}
  }
  const all = readFileMemory();
  const k = String(uid ?? 'gast');
  const before = (all[k] || []).length;
  all[k] = (all[k] || []).filter((f) => !String(f).toLowerCase().includes(needle.toLowerCase()));
  try {
    fs.writeFileSync(memoryFile(), JSON.stringify(all, null, 2));
  } catch (_) {}
  return before - all[k].length;
}

// Directe, GEEN model nodig: instant antwoorden voor de dingen die we beter zelf kunnen.
async function quickReply(message, req) {
  const v = versionInfo();
  const base = process.env.PUBLIC_URL
    ? String(process.env.PUBLIC_URL).replace(/\/$/, '')
    : `${req.protocol}://${req.get('host')}`;
  const m = message.toLowerCase().trim();

  if (/^(hoi|hallo|hey|hai|yo|hallo daar)\b/.test(m) && m.length < 24) {
    return 'Hoi! Waar kan ik je mee helpen? 🐺';
  }
  if (m.includes('help') || m.includes('wat kun je') || m.includes('wat kan je')) {
    return 'Dit kan ik voor je doen:\n' +
      '• Vragen beantwoorden en uitleg geven\n' +
      '• Code en scripts schrijven — zeg bv. "maak een Python-script dat …"\n' +
      '• Live zoeken: "zoek <onderwerp> op"\n' +
      '• Onthouden: "onthoud dat …" en "wat weet je van me"\n' +
      '• Apps downloaden: typ "download" in WolfPulse\n' +
      '• Op je Mini-PC werken: "voer uit: maak een script dat …" — ik maak een plan en jij geeft toestemming\n' +
      `• Status: CyberWolfert ${v.version || '?'} (build ${v.build || '?'})`;
  }
  if (m.includes('wie ben je') || m.includes('je naam') || m.includes('welk model') ||
      m.includes('hoe heet je') || m.includes('hoe heet jij') || m.includes('ben jij een ai')) {
    return 'Ik ben CyberWolf AI, de vaste assistent van de CyberWolfert Browser. 🐺 Ik draai zelf op jouw Mini-PC.';
  }
  const naamIs = m.match(/(?:mijn naam is|ik heet|noem me)\s+(.+)/);
  if (naamIs && naamIs[1].trim().length > 1 && naamIs[1].trim().length < 40) {
    const naam = naamIs[1].trim().replace(/\s+(op|naar|eens|even)$/, '').trim();
    const uid = await effectiveUserId(req);
    await saveMemory(uid, `mijn naam is ${naam}`);
    const mooi = naam.charAt(0).toUpperCase() + naam.slice(1);
    return `Leuk je te ontmoeten, ${mooi}! 🐺 Ik heb het onthouden.`;
  }
  if (m.includes('hoe heet ik') || m.includes('weet je mijn naam') ||
      m.includes('hoe denk je dat ik heet') || m.includes('wat is mijn naam')) {
    const uid = await effectiveUserId(req);
    const feiten = await getMemory(uid);
    const naamFeit = feiten.find((f) => /naam is/i.test(f));
    if (naamFeit) {
      const nm = naamFeit.replace(/.*naam is\s+/i, '').trim();
      return `Jij bent ${nm}! 🐺 (Dat heb je me zelf verteld.)`;
    }
    return 'Dat weet ik nog niet! Zeg "mijn naam is ..." en ik vergeet het nooit meer. 🐺';
  }
  if (m.includes('download') || m.includes('apk') || m.includes('installeren') || m.includes('exe')) {
    return `Apps downloaden kan zo:\n• Typ het codewoord "download" in de WolfPulse-zoekbalk, of\n• Open direct: ${base}/downloads/CyberWolfert-apps.zip\nDaarin zit de Android-APK, Windows-versie en uitleg.`;
  }
  if (m.includes('versie') || m.includes('update')) {
    return `We draaien CyberWolfert ${v.version || '?'} (build ${v.build || '?'}). ` +
      'Bij een nieuwe publish krijg je een update-melding bij het opstarten.';
  }
  const onthoud = m.match(/onthoud\s+(?:dat\s+)?(.+)/);
  if (onthoud && onthoud[1].trim().length > 1 && onthoud[1].trim().length < 200) {
    const uid = await effectiveUserId(req);
    await saveMemory(uid, onthoud[1].trim());
    return `Onthouden! 🧠${uid ? ' Ik bewaar dit bij jouw account.' : ' Ik bewaar dit op dit apparaat (log in om het per account te bewaren).'} Vraag "wat weet je van me" om alles te zien.`;
  }
  if (m.includes('wat weet je') || m.includes('wat heb je onthouden') || m.includes('mijn geheugen')) {
    const uid = await effectiveUserId(req);
    const feiten = await getMemory(uid);
    if (!feiten.length) return 'Ik heb nog niets over je onthouden. Zeg "onthoud dat ..." en ik bewaar het.';
    return `Dit weet ik van je:\n• ${feiten.join('\n• ')}\n\nZeg "vergeet ..." om iets te wissen.`;
  }
  const vergeet = m.match(/vergeet\s+(.+)/);
  if (vergeet && vergeet[1].trim().length > 0) {
    const uid = await effectiveUserId(req);
    const n = await forgetMemory(uid, vergeet[1].trim());
    return n > 0 ? `Vergeten! (${n} item(s) gewist.)` : 'Daarvan heb ik niets opgeslagen staan.';
  }
  if (/^(hoe laat|wat is de tijd|welke dag|datum vandaag|wat is de datum)/.test(m)) {
    const nu = new Date();
    return `Het is nu ${nu.toLocaleTimeString('nl-NL')} op ${nu.toLocaleDateString('nl-NL', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}.`;
  }
  const zoek = m.match(/(?:zoek|search|zoek op|zoek eens)(?:\s+(?:eens|op|naar|voor me|even))?\s+(.+)/) ||
               m.match(/^(.+?)\s+(opzoeken|zoeken)$/);
  if (zoek) {
    const q = (zoek[1] || zoek[2] || '').trim().replace(/\s+(op|naar|eens|even|voor me)$/, '').trim();
    if (q) {
      const results = await globalSearch(q);
      if (!results.length) return `Niets gevonden voor "${q}". Probeer een andere zoekterm.`;
      const top = results.slice(0, 5)
        .map((r, i) => `${i + 1}. ${r.title}\n   ${r.url}${r.snippet ? `\n   ${r.snippet.slice(0, 140)}` : ''}`)
        .join('\n');
      return `Dit vond WolfPulse voor "${q}":\n${top}\n\nTik op een resultaat om het in CyberWolfert te openen.`;
    }
  }
  if (m.includes('wolfpulse') || m.includes(' zoekmachine')) {
    return 'WolfPulse is onze eigen zoekmachine: eigen links eerst, daarna resultaten via SearXNG/DuckDuckGo/Wikipedia. Alles loopt via jouw Mini-PC.';
  }
  if (m.includes('dank')) return 'Graag gedaan! 🐺 Waar kan ik je nog mee helpen?';
  if (/^(test|hallo+$|hey+$|hoi+$|ok|oké|ja|nee|hmm+|super|top)\.?$/.test(m)) {
    const variants = [
      'Ik ben er! 🐺 Stel me een vraag, zeg "zoek <onderwerp> op" of typ "help".',
      'Hoi hoi! 🐺 Waar kan ik je mee helpen?',
      'Aangesloten en klaar! 🐺 Vraag me iets, of laat me iets opzoeken.',
    ];
    let h = 0;
    for (const ch of m) h = (h * 31 + ch.codePointAt(0)) % 997;
    return variants[h % variants.length];
  }
  return null;
}

async function webContext(message, codeMode) {
  if (codeMode) return '';
  if (!isLookupAsk(message)) return '';
  try {
    const results = await Promise.race([
      globalSearch(message.replace(/[?]+$/, '').slice(0, 120)),
      new Promise((_, rej) => setTimeout(() => rej(new Error('slow')), 3500)),
    ]);
    if (!results || !results.length) return '';
    const top = results.slice(0, 3)
      .map((r) => `- ${r.title}: ${r.snippet || ''} (${r.url})`)
      .join('\n');
    return `\nLive zoekresultaten van WolfPulse (gebruik als het klopt, verzin niets):\n${top}`;
  } catch (_) {
    return '';
  }
}

async function logChat(message, reply, req) {
  try {
    const uid = await effectiveUserId(req);
    if (uid) {
      await db.query('INSERT INTO ai_chats (user_id, role, content) VALUES ($1,$2,$3)', [uid, 'user', message]);
      await db.query('INSERT INTO ai_chats (user_id, role, content) VALUES ($1,$2,$3)', [uid, 'assistant', reply]);
    }
  } catch (_) {}
}

router.get('/status', async (req, res) => {
  const v = versionInfo();
  let models = [];
  try {
    const r = await fetchTimeout(
      (process.env.OLLAMA_URL || 'http://127.0.0.1:11434/api/chat').replace(/\/api\/chat$/, '/api/tags'),
      {}, 4000);
    if (r.ok) models = (await r.json()).models?.map((m) => m.name) || [];
  } catch (_) {}
  res.json({
    ollama: models.length > 0,
    models,
    chatModel: process.env.OLLAMA_MODEL || 'qwen2.5:1.5b',
    codeModel: process.env.AI_CODE_MODEL || 'qwen2.5-coder:3b',
    vision: !!process.env.OLLAMA_VISION_MODEL || models.some((m) => /vl|llava|vision/.test(m)),
    known: KNOWN_MODELS,
    version: v.version,
    build: v.build,
  });
});

router.post('/chat', uploadAi.single('image'), async (req, res) => {
  let { message, history } = req.body || {};
  if (typeof history === 'string') {
    try {
      history = JSON.parse(history);
    } catch {
      history = [];
    }
  }
  if (!message) return res.status(400).json({ error: 'missing_message' });

  let imageB64 = null;
  let imageUrl = null;
  if (req.file) {
    const base = process.env.PUBLIC_URL
      ? String(process.env.PUBLIC_URL).replace(/\/$/, '')
      : `${req.protocol}://${req.get('host')}`;
    imageUrl = `${base}/uploads/${req.file.filename}`;
    try {
      imageB64 = fs.readFileSync(req.file.path).toString('base64');
    } catch (_) {}
  }

  // 1) Instant antwoorden (zo snel als lokaal mogelijk)
  if (!imageB64) {
    try {
      const quick = await quickReply(message, req);
      if (quick) {
        logChat(message, quick, req);
        log.ai(await naamOf(await effectiveUserId(req)), message, 'quick');
        return res.json({ assistant: 'CyberWolf AI', reply: quick, engine: 'quick', code: false });
      }
    } catch (e) {
      console.warn('[ai] quick failed:', e.message);
    }
  }

  const codeMode = isCodeAsk(message);
  let memoryLine = '';
  try {
    const uid = await effectiveUserId(req);
    const feiten = await getMemory(uid);
    if (feiten.length) memoryLine = `\nDingen die je over deze gebruiker weet: ${feiten.join('; ')}.`;
  } catch (_) {}

  const ctx = await webContext(message, codeMode);
  const sys = IDENTITY + '\n' + STYLE + (codeMode ? '\n' + CODING : '') +
    memoryLine + ctx +
    `\nHet is nu ${new Date().toLocaleString('nl-NL')}. CyberWolfert ${versionInfo().version}.`;
  const messages = [
    { role: 'system', content: sys },
    ...(Array.isArray(history) ? history.slice(-10) : []),
    { role: 'user', content: message },
  ];

  let out = null;
  if (imageB64) {
    try {
      out = await ollamaVision(messages, imageB64);
    } catch (e) {
      console.warn('[ai] vision failed:', e.message);
    }
  }
  if (!out) {
    for (const fn of [
      () => ollamaChat(messages, codeMode),
      () => ollamaChat(messages, false),
      openaiCompatChat,
    ]) {
      try {
        out = await fn();
        break;
      } catch (e) {
        console.warn('[ai] engine failed:', e.message);
      }
    }
  }
  if (!out) {
    try {
      let reply = await fallbackReply(message, req, codeMode);
      if (imageUrl) {
        reply += `\n\n🖼️ Afbeelding bewaard als ${imageUrl.split('/').pop()}. ` +
          'Voor echte beeldbeschrijving zet je een vision-model op de Mini-PC (OLLAMA_VISION_MODEL).';
      }
      out = { reply, engine: 'local' };
    } catch (e) {
      console.error(e);
      return res.status(500).json({ assistant: 'CyberWolf AI', error: 'ai_failed' });
    }
  }
  logChat(imageUrl ? `${message} [afbeelding: ${imageUrl}]` : message, out.reply, req);
  log.ai(await naamOf(await effectiveUserId(req)), message, out.engine);
  res.json({
    assistant: 'CyberWolf AI',
    reply: out.reply,
    engine: out.engine,
    code: codeMode,
    imageUrl,
  });
});

async function fallbackReply(message, req, codeMode) {
  const uid = await effectiveUserId(req);
  const feiten = await getMemory(uid);
  const v = versionInfo();
  if (codeMode) {
    return 'Ik draai nu zonder model, dus ik kan de code niet zelf genereren. ' +
      'Zet Ollama aan op de Mini-PC (model: qwen2.5-coder:3b) en probeer het opnieuw — dan schrijf ik het script meteen voor je. ' +
      `CyberWolfert ${v.version}.`;
  }
  return 'Ik draai nu in lokale modus (geen Ollama verbonden), maar ik kan wel: ' +
    'zoeken via WolfPulse ("zoek <onderwerp> op"), uitleg geven ("help"), geheugen ("onthoud dat ...") en downloads regelen ("download")' +
    (feiten.length ? `.\nWat ik van je weet: ${feiten.slice(0, 3).join('; ')}` : '.');
}

module.exports = router;
