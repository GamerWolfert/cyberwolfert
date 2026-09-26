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

const SYSTEM_PROMPT =
  'Je bent CyberWolf AI, de ingebouwde assistent van de CyberWolfert Browser met WolfPulse-zoekmachine. ' +
  'Noem jezelf in elke chat ALLEEN CyberWolf AI. Zeg nooit Llama, Ollama, ChatGPT, Qwen of een andere modelnaam. ' +
  'Antwoord ALTIJD kort (maximaal ~80 woorden), behulpzaam, in het Nederlands tenzij de gebruiker anders vraagt. ' +
  'Handige feiten: codewoord "download" in WolfPulse geeft de apps-zip; ' +
  'de browser draait op de Mini-PC van de gebruiker met alles lokaal.';

function fetchTimeout(url, opts = {}, ms = 25000) {
  const c = new AbortController();
  const t = setTimeout(() => c.abort(), ms);
  return fetch(url, { ...opts, signal: c.signal }).finally(() => clearTimeout(t));
}

async function ollamaChat(messages) {
  const r = await fetchTimeout(process.env.OLLAMA_URL || 'http://192.168.1.42:11434/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: process.env.OLLAMA_MODEL || 'llama3', messages, stream: false, options: { num_predict: 300 } }),
  }, 60000);
  if (!r.ok) throw new Error(`ollama http ${r.status}`);
  const j = await r.json();
  const reply = j.message?.content || j.response;
  if (!reply) throw new Error('ollama empty');
  return { reply, engine: 'ollama' };
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
  if (!process.env.OLLAMA_VISION_MODEL) throw new Error('no vision model configured');
  const msgs = messages.map((mm) => ({ ...mm }));
  msgs[msgs.length - 1] = { ...msgs[msgs.length - 1], images: [imageB64] };
  const r = await fetchTimeout(process.env.OLLAMA_URL || 'http://192.168.1.42:11434/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: process.env.OLLAMA_VISION_MODEL, messages: msgs, stream: false }),
  }, 90000);
  if (!r.ok) throw new Error(`vision http ${r.status}`);
  const j = await r.json();
  const reply = j.message?.content || j.response;
  if (!reply) throw new Error('vision empty');
  return { reply, engine: 'ollama-vision' };
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

async function localAssistant(message, req) {
  const v = versionInfo();
  const base = process.env.PUBLIC_URL
    ? String(process.env.PUBLIC_URL).replace(/\/$/, '')
    : `${req.protocol}://${req.get('host')}`;
  const m = message.toLowerCase().trim();

  if (/^(hoi|hallo|hey|hai|yo)\b/.test(m) && m.length < 20) {
    return 'Hoi! Ik ben CyberWolf AI 🐺. Stel me een vraag, laat me iets opzoeken via WolfPulse (bv. "zoek katten op"), of typ "help" voor alles wat ik kan.';
  }
  if (m.includes('help') || m.includes('wat kun je') || m.includes('wat kan je')) {
    return 'Dit kan ik voor je doen:\n' +
      '• Vragen beantwoorden over de browser, WolfPulse en updates\n' +
      '• Live zoeken: zeg "zoek <onderwerp> op" en ik geef de beste resultaten\n' +
      '• Apps downloaden: typ "download" in WolfPulse voor de alles-in-1 zip\n' +
      `• Status: CyberWolfert ${v.version || '?'} (build ${v.build || '?'})\n` +
      'Tip: verbind de Mini-PC met Ollama en ik word nog slimmer.';
  }
  if (m.includes('wie ben je') || m.includes('je naam') || m.includes('welk model') ||
      m.includes('hoe heet je') || m.includes('hoe heet jij')) {
    return 'Ik ben CyberWolf AI, de vaste assistent van de CyberWolfert Browser. 🐺';
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
    return `Apps downloaden kan zo:\n• Typ het codewoord "download" in de WolfPulse-zoekbalk, of\n• Open direct: ${base}/downloads/CyberWolfert-apps.zip\nDaarin zit de Android-APK, Windows-versie en uitleg voor Chromebook.`;
  }
  if (m.includes('versie') || m.includes('update')) {
    return `We draaien CyberWolfert ${v.version || '?'} (build ${v.build || '?'}). ` +
      'Bij een nieuwe publish krijg je automatisch een update-melding bij het opstarten. ' +
      'De website is altijd meteen bijgewerkt.';
  }
  const zoek = m.match(/(?:zoek|search|zoek op|zoek eens)(?:\s+(?:eens|op|naar|voor me|even))?\s+(.+)/) ||
               m.match(/^(.+?)\s+(opzoeken|zoeken)$/);
  if (zoek) {
    let q = (zoek[1] || zoek[2] || '').trim().replace(/\s+(op|naar|eens|even|voor me)$/, '').trim();
    if (q) {
      const results = await globalSearch(q);
      if (!results.length) return `Niets gevonden voor "${q}". Probeer een andere zoekterm.`;
      const top = results.slice(0, 5)
        .map((r, i) => `${i + 1}. ${r.title}\n   ${r.url}${r.snippet ? `\n   ${r.snippet.slice(0, 140)}` : ''}`)
        .join('\n');
      return `Dit vond WolfPulse voor "${q}":\n${top}\n\nTik op een resultaat om het in CyberWolfert te openen.`;
    }
  }
  if (m.includes('wolfpulse') || m.includes('zoekmachine')) {
    return 'WolfPulse is onze eigen zoekmachine: eigen links eerst, daarna wereldwijde resultaten ' +
      'via SearXNG/Bing (of gratis via DuckDuckGo en Wikipedia als die er niet zijn). Alles loopt via jouw Mini-PC.';
  }
  if (m.includes('dank')) return 'Graag gedaan! 🐺 Waar kan ik je nog mee helpen?';
  const onthoud = m.match(/onthoud\s+(?:dat\s+)?(.+)/);
  if (onthoud && onthoud[1].trim().length > 1) {
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
  if (vergeet) {
    const uid = await effectiveUserId(req);
    const n = await forgetMemory(uid, vergeet[1].trim());
    return n > 0 ? `Vergeten! (${n} item(s) gewist.)` : 'Daarvan heb ik niets opgeslagen staan.';
  }
  if (/^(test|hallo+$|hey+$|hoi+$|ok|oké|ja|nee|hmm+)\.?$/.test(m)) {
    const variants = [
      'Ik ben er! 🐺 Stel me een vraag, zeg "zoek <onderwerp> op" of typ "help".',
      'Hoi hoi! 🐺 Waar kan ik je mee helpen? (Tip: "help" laat alles zien.)',
      'Aangesloten en klaar! 🐺 Vraag me iets, of laat me iets opzoeken.',
    ];
    let h = 0;
    for (const ch of m) h = (h * 31 + ch.codePointAt(0)) % 997;
    return variants[h % variants.length];
  }
  return 'Ik draai nu in lokale modus (geen Ollama verbonden), maar ik kan wel: ' +
    'zoeken via WolfPulse ("zoek <onderwerp> op"), uitleg geven ("help") en downloads regelen ("download"). ' +
    'Wat wil je doen?';
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

  let memoryLine = '';
  try {
    const uid = await effectiveUserId(req);
    const feiten = await getMemory(uid);
    if (feiten.length) memoryLine = `\nDingen die je over deze gebruiker weet: ${feiten.join('; ')}.`;
  } catch (_) {}
  const messages = [
    { role: 'system', content: SYSTEM_PROMPT + memoryLine },
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
    for (const fn of [ollamaChat, openaiCompatChat]) {
      try {
        out = await fn(messages);
        break;
      } catch (e) {
        console.warn('[ai] engine failed:', e.message);
      }
    }
  }
  if (!out) {
    try {
      let reply = await localAssistant(message, req);
      if (imageUrl && !process.env.OLLAMA_VISION_MODEL) {
        if (/beschrijf|wat zie je|foto|afbeelding|plaatje/i.test(message)) {
          reply = `🖼️ Mooie upload! Ik zie dat je me een afbeelding stuurde (bewaard als ${imageUrl.split('/').pop()}). ` +
            `Echt kijken kan ik pas met een vision-model op de Mini-PC (zet OLLAMA_VISION_MODEL, bv. llava) — dan beschrijf ik alles tot in detail. Tot die tijd: stel me gerust andere vragen! 🐺`;
        } else {
          reply += `\n\n🖼️ Afbeelding ontvangen en bewaard. Wil je echte beeldbeschrijving? Zet een vision-model op de Mini-PC (OLLAMA_VISION_MODEL, bv. llava) en ik beschrijf alles wat je stuurt.`;
        }
      }
      out = { reply, engine: 'local' };
    } catch (e) {
      console.error(e);
      return res.status(500).json({ assistant: 'CyberWolf AI', error: 'ai_failed' });
    }
  }
  logChat(imageUrl ? `${message} [afbeelding: ${imageUrl}]` : message, out.reply, req);
  log.ai(await naamOf(await effectiveUserId(req)), message, out.engine);
  res.json({ assistant: 'CyberWolf AI', reply: out.reply, engine: out.engine, imageUrl });
});

module.exports = router;
