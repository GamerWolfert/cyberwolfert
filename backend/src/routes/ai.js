// AeroNova AI: Ollama -> OpenAI-compat -> lokale slimme modus (met geheugen).
// Presenteert zich ALTIJD als "AeroNova AI".
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
  'Je bent AeroNova AI, de vaste slimme assistent van de AeroSurf Browser. ' +
  'Je hebt een eigen Mini-PC (Linux) met internet, PostgreSQL, Ollama en Discord-logging.';

const STYLE =
  'Regels: noem jezelf ALLEEN AeroNova AI (nooit een modelnaam). Perfect Nederlands, ' +
  'aanspreekvorm "je" (nooit "u"), altijd eerste persoon (ik/mij), respectvol en hartelijk. ' +
  'Gewone antwoorden: maximaal 3 zinnen, kort en to-the-point, geen herhaling. ' +
  'Op een simpele groet precies één vrolijke zin, bv. "Hoi! Waar kan ik je mee helpen?" ' +
  'Wees eerlijk: weet je het niet zeker, zeg dat gewoon. ' +
  'Zeg NOOIT "dat kan ik niet", "ik kan je niet helpen" of "sorry, ik heb geen kennis": ' +
  'lever gewoon de code, het bestand of de stappen. ' +
  'Kan iets alleen op een computer, verwijs dan naar "voer uit: <doel>" zodat de Mini-PC het doet. ' +
  'Maak je een bestand, geef dan het complete script plus het commando om het te draaien.';

const CODING =
  'Code-regels: je bent een uitstekende programmeur (Python, JavaScript/TypeScript, Dart/Flutter, ' +
  'HTML/CSS, SQL, Bash, C#). Geef ALTIJD complete, werkende code — nooit fragments of "...". ' +
  'Zet code in een codeblok met de juiste taal-tag (```python) en erbij hoe je het uitvoert ' +
  '(bestandsnaam + commando). Uitleg in max 5 korte zinnen, daarna de code. ' +
  'Veilige standaarden: geen wachtwoordsleutels in code. ' +
  'Schrijf het bestand weg als dat nodig is (printf/cat in bash of open(...).write(...) in Python).';

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
  if (s.length > 600) return false;
  if (/```/.test(m)) return true;
  // Bestand/terminal-acties tellen altijd als codevraag.
  if (/\b(txt|bestand|bestanden|map|folder|script|shell|commando|run|uitvoeren|draai(en)?)\b/.test(s) &&
      /\b(maak|schrijf|cre[eë]er|voeg|run|uitvoeren|draai|genereer|herschrijf|verwijder|lees|tel|zip|backup)\b/.test(s)) return true;
  return /\b(script|code|coderen|codeer|programma|functie|klasse|class |function |def |const |let |var |import |export |html|css|javascript|typescript|python|dart|flutter|sql|bash|shell|powershell|regex|api|endpoint|compile|foutmelding|error|exception|stacktrace|debug|bug|refactor|widget|component)\b/.test(s) &&
    /\b(maak|schrijf|geef|bouw|fix|herstel|fout|foutje|uitleg|hoe|help|cre[eë]er|toon|genereer|nodig|script|code|kan|kunt|zou|zou je|wil)\b/.test(s) ||
    /maak.*(script|code|programma|bestand)/.test(s);
}

// Model dat "sorry, ik kan niet" teruggeeft: opnieuw proberen met de coder
// en een harde regel ertegen — dat is het echte probleem van de AI.
function isRefusal(reply) {
  const s = String(reply || '').toLowerCase().trim();
  if (!s || s.length > 700) return false;
  if (/\b```/.test(s)) return false; // er zit code in, dus hulp is wél geleverd
  return /\b(sorry|het spijt)\b[^.]{0,80}\b(niet|geen)\b/.test(s) ||
    /\b(ik kan (je |het |dat )?niet|dat kan ik niet|ik ben niet in staat|geen ervaring met|geen kennis|ik kan alleen helpen met andere|ik weet niet hoe ik|hapert)\b/.test(s);
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
  // Modellen blijven 24u geladen (OLLAMA_KEEP_ALIVE in de service): elk verzoek
  // zonder meer hoeven laden kost anders 2-4s extra.
  const keep = process.env.OLLAMA_KEEP_ALIVE || '24h';
  const opts = codeMode
    ? { num_predict: 1600, temperature: 0.15, top_p: 0.9, num_ctx: 4096, repeat_penalty: 1.05, keep_alive: keep }
    : { num_predict: 220, temperature: 0.3, top_p: 0.9, num_ctx: 2048, repeat_penalty: 1.1, keep_alive: keep };

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
  if (process.env.AI_TIMING === '1') {
    const tok = (s) => (s ? Math.round(s / 1e6) : 0);
    console.log(
      `[ai-timing] ${model} prompt=${j.prompt_eval_count}tok/${tok(j.prompt_eval_duration)}ms ` +
        `gen=${j.eval_count}tok/${tok(j.eval_duration)}ms totaal=${tok(j.total_duration)}ms cache=${j.prompt_eval_count === 0 ? 'hit' : 'miss'}`
    );
  }
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
      const r = await db.query('SELECT feit FROM ai_memory WHERE user_id=$1 ORDER BY id DESC LIMIT 10', [uid]);
      return r.rows.map((x) => x.feit);
    } catch (_) {}
  }
  return readFileMemory()[String(uid ?? 'gast')] || [];
}

// Wie is de gebruiker? Naam, e-mail, admin, vrienden, servers, mailboxen,
// recente zoekopdrachten en laatste AI-gesprekken -> kort blok voor de prompt.
async function profileContextUncached(uid, alsPrompt = true) {
  if (!uid) {
    return alsPrompt
      ? '\nJe praat met een gast (niet ingelogd): je weet niets over een account.'
      : 'Je bent niet ingelogd, dus ik ken je account nog niet.';
  }
  const q = async (sql, args) => {
    try {
      const r = await db.query(sql, args);
      return r.rows;
    } catch (_) {
      return [];
    }
  };
  const [u] = await q(
    'SELECT username, display_name, email, email_verified, is_admin, created_at FROM users WHERE id=$1',
    [uid]
  );
  if (!u) return '';
  const [friends, servers, owned, boxes, searches, chats, groups] = await Promise.all([
    q(
      `SELECT COALESCE(p.display_name, f.display_name, uf.username) AS naam, uf.username
         FROM ws_friends fr
         JOIN users uf ON uf.id = fr.friend_id
         LEFT JOIN ws_profiles p ON p.user_id = uf.id
         LEFT JOIN users f ON f.id = uf.id
        WHERE fr.user_id=$1 LIMIT 8`,
      [uid]
    ),
    q(
        `SELECT DISTINCT s.name FROM ws_members m JOIN ws_servers s ON s.id=m.server_id
        WHERE m.user_id=$1 ORDER BY s.name LIMIT 6`,
      [uid]
    ),
    q('SELECT DISTINCT name FROM ws_servers WHERE owner_id=$1 ORDER BY name LIMIT 6', [uid]),
    q(
      `SELECT LOWER(mb.localpart) || '@' || LOWER(d.domain) AS address
         FROM mail_mailboxes mb JOIN mail_domains d ON d.id=mb.domain_id
        WHERE mb.owner_user_id=$1 LIMIT 5`,
      [uid]
    ),
    q('SELECT query FROM search_history WHERE user_id=$1 ORDER BY id DESC LIMIT 5', [uid]),
    q(
      `SELECT role, content FROM ai_chats WHERE user_id=$1 ORDER BY id DESC LIMIT 5`,
      [uid]
    ),
    q(
      `SELECT g.name FROM ws_groups g JOIN ws_group_members gm ON gm.group_id=g.id
        WHERE gm.user_id=$1 LIMIT 4`,
      [uid]
    ),
  ]);

  const naam = (u.display_name || u.username || '').trim();
  const regels = [];
  regels.push(
    alsPrompt
      ? `De gebruiker heet ${naam} (username: ${u.username})` +
          (u.email ? `, e-mail/adres: ${u.email}` : '') +
          (u.email_verified ? ' (bevestigd)' : '') +
          `.`
      : `Jij bent ${naam || u.username} (@${u.username})` +
          (u.email ? `, e-mail: ${u.email}${u.email_verified ? ' (bevestigd)' : ''}` : '') +
          `.`
  );
  regels.push(
    u.is_admin
      ? alsPrompt
        ? 'Dit is een ADMINISTRATOR van AeroSurf: je mag hem/haar als beheerder aanspreken en admin-acties voorstellen.'
        : 'Je bent ADMINISTRATOR van AeroSurf.'
      : alsPrompt
        ? 'Dit is een gewone gebruiker (geen admin).'
        : 'Je bent een gewone gebruiker (geen admin).'
  );
  if (friends.length) {
    regels.push(
      `Vrienden: ${friends.map((f) => `${f.naam || f.username} (@${f.username})`).join(', ')}.`
    );
  }
  const ownedNames = owned.map((s) => s.name);
  const memberNames = servers.map((s) => s.name).filter((n) => !ownedNames.includes(n));
  if (ownedNames.length) regels.push(`Eigen servers: ${ownedNames.join(', ')}.`);
  if (memberNames.length) regels.push(`Servers waar hij/zij in zit: ${memberNames.join(', ')}.`);
  if (groups.length) regels.push(`Groeps-chats: ${groups.map((g) => g.name).join(', ')}.`);
  if (boxes.length) {
    const l = alsPrompt ? 'Zijn/haar mailadressen' : 'Jouw mailadressen';
    regels.push(`${l}: ${boxes.map((b) => b.address).join(', ')}.`);
  }
  const zoekUniek = [...new Set(searches.map((s) => s.query).filter(Boolean))].slice(0, 5);
  if (zoekUniek.length) {
    regels.push(`Recent gezocht in AeroSeek: ${zoekUniek.join('; ')}.`);
  }
  if (chats.length && alsPrompt) {
    const laatste = chats
      .slice()
      .reverse()
      .slice(0, 3)
      .map((c) => `${c.role === 'user' ? 'ik' : 'jij'}: ${String(c.content).slice(0, 60)}`);
    regels.push(`Eerdere gesprekken (nieuwste eerst): ${laatste.join(' | ')}.`);
  }
  if (!regels.length) return alsPrompt ? '' : 'Ik weet nog niets over je account.';
  return alsPrompt
    ? `\nOver de gebruiker (gebruik dit als iemand over zichzelf vraagt):\n- ` + regels.join('\n- ')
    : `Over jouw account weet ik dit:\n�?� ` + regels.join('\n�?� ');
}

// Profielcontext cachen (60s): scheelt 8 parallelle queries per AI-bericht en
// houdt het systeembericht stabiel, waardoor Ollama de KV-prefix-cache kan
// hergebruiken (prompt-eval is veruit het duurste onderdeel).
const profielCache = new Map();
async function profileContext(uid, alsPrompt = true) {
  if (!uid) return profileContextUncached(uid, alsPrompt);
  const key = `${uid}:${alsPrompt ? 1 : 0}`;
  const hit = profielCache.get(key);
  if (hit && Date.now() - hit.t < 60000) return hit.txt;
  const txt = await profileContextUncached(uid, alsPrompt);
  profielCache.set(key, { t: Date.now(), txt });
  if (profielCache.size > 500) profielCache.clear();
  return txt;
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
function fmtNum(n) {
  if (!isFinite(n)) return null;
  if (Number.isInteger(n)) return n.toLocaleString('nl-NL');
  return Number(n.toFixed(6)).toLocaleString('nl-NL', { maximumFractionDigits: 6 });
}

// Veilige rekenmachine: herkent "wat is 1000x2", "20% van 150", "(3+4)*2" ...
function quickMath(raw) {
  let s = raw.toLowerCase().trim()
    .replace(/[?]+$/, '')
    .replace(/\b(hoi+|hallo+|hey+|hai+|yo+|oké|ok)\b/g, ' ')
    .replace(/\b(wat is|wat wordt|bereken|uitkomst van|reken(?: uit| uit eens)?|hoeveel is|wat zijn)\b/g, ' ')
    .replace(/(\d)\s*[x×]\s*(?=\d)/g, '$1*')
    .replace(/\bkeer\b/g, '*')
    .replace(/\bgedeeld door\b/g, '/')
    .replace(/\bplus\b/g, '+')
    .replace(/\bmin\b/g, '-')
    .replace(/\bvermenigvuldigd met\b|\bmaal\b|\bx\b/g, '*')
    .replace(/\bprocent\b/g, '%')
    .replace(/\s+/g, ' ')
    .trim();
  if (!s || s.length > 80) return null;

  // "20% van 150" / "12,5 procent van 80"
  const pct = s.match(/^(\d+(?:[.,]\d+)?)\s*%\s*van\s+(\d+(?:[.,]\d+)?)$/);
  if (pct) {
    const a = parseFloat(pct[1].replace(',', '.'));
    const b = parseFloat(pct[2].replace(',', '.'));
    const r = fmtNum((a / 100) * b);
    if (r) return `${fmtNum(a)}% van ${fmtNum(b)} = ${r}`;
  }

  if (!/^[\d\s+\-*/^().,%]+$/.test(s)) return null;
  if (!/\d/.test(s) || !/[+\-*/^%]/.test(s)) return null;
  if (/^\s*\d+(\.\d+)?\s*$/.test(s)) return null;

  const expr = s.replace(/,/g, '.').replace(/\s+/g, '');
  try {
    const val = evalMath(expr);
    const r = fmtNum(val);
    if (!r) return null;
    const nice = expr.replace(/\*/g, '×').replace(/\//g, '÷').replace(/\^/g, '^');
    return `${nice} = ${r}`;
  } catch (_) {
    return null;
  }
}

function evalMath(expr) {
  let i = 0;
  function peek() { return expr[i]; }
  function eat(c) { if (expr[i] === c) { i++; return true; } return false; }
  function expr_() {
    let v = term();
    for (;;) {
      if (eat('+')) v += term();
      else if (eat('-')) v -= term();
      else return v;
    }
  }
  function term() {
    let v = unary();
    for (;;) {
      if (eat('*')) v *= unary();
      else if (eat('/')) v /= unary();
      else if (eat('%')) v %= unary();
      else return v;
    }
  }
  function unary() {
    if (eat('-')) return -unary();
    if (eat('+')) return unary();
    return power();
  }
  function power() {
    const base = primary();
    if (eat('^')) return Math.pow(base, unary());
    return base;
  }
  function primary() {
    if (eat('(')) { const v = expr_(); if (!eat(')')) throw new Error('paren'); return v; }
    let start = i;
    while (i < expr.length && /[\d.]/.test(expr[i])) i++;
    if (start === i) throw new Error('number');
    const n = parseFloat(expr.slice(start, i));
    if (Number.isNaN(n)) throw new Error('nan');
    return n;
  }
  const out = expr_();
  if (i !== expr.length || !isFinite(out)) throw new Error('parse');
  return out;
}

// Snel profiel-antwoord: wie ben ik, mijn e-mail, admin?, vrienden, servers.
// Uit de database, zonder dat het model hoeft te draaien.
async function profileQuick(m, req) {
  const vraag =
    /\b(wie ben ik|hoe heet ik|wat is mijn naam|wat is mijn e-mail|mijn mailadres|wat is mijn emailadres|ben ik admin|ben ik een admin|welke servers heb ik|wie zijn mijn vrienden|wat is mijn gebruikersnaam)\b/.test(m);
  if (!vraag) return null;
  let uid = null;
  try {
    uid = await effectiveUserId(req);
  } catch (_) {}
  if (!uid) return 'Je bent niet ingelogd, dus ik ken je account nog niet. Log in dan weet ik wie je bent.';
  let u = null;
  try {
    const r = await db.query(
      'SELECT username, display_name, email, is_admin FROM users WHERE id=$1',
      [uid]
    );
    u = r.rows[0];
  } catch (_) {}
  if (!u) return 'Ik kan je account niet vinden.';

  const naam = (u.display_name || u.username || '').trim();
  if (/welke servers/.test(m) || /wie zijn mijn vrienden/.test(m)) {
    let regels = [];
    try {
      const s = await db.query(
        'SELECT DISTINCT s.name FROM ws_members m JOIN ws_servers s ON s.id=m.server_id WHERE m.user_id=$1 ORDER BY s.name LIMIT 12',
        [uid]
      );
      const f = await db.query(
        `SELECT COALESCE(p.display_name, uf.username) AS naam, uf.username
           FROM ws_friends fr JOIN users uf ON uf.id=fr.friend_id
           LEFT JOIN ws_profiles p ON p.user_id=uf.id
          WHERE fr.user_id=$1 LIMIT 15`,
        [uid]
      );
      if (s.rows.length) regels.push(`Servers: ${s.rows.map((x) => x.name).join(', ')}.`);
      if (f.rows.length) {
        regels.push(`Vrienden: ${f.rows.map((x) => `${x.naam} (@${x.username})`).join(', ')}.`);
      }
    } catch (_) {}
    if (!regels.length) return `Je zit nog nergens in en hebt nog geen vrienden, ${naam || 'vriend'}.`;
    return `Je heet ${naam} (@${u.username}).\n- ` + regels.join('\n- ');
  }
  if (/admin/.test(m)) {
    return u.is_admin
      ? `Ja, ${naam || u.username}, jij bent ADMINISTRATOR van AeroSurf. 🐺`
      : `Nee, ${naam || u.username}, je bent een gewone gebruiker (geen admin).`;
  }
  if (/e-?mail|mailadres/.test(m)) {
    return u.email
      ? `Jouw e-mailadres is ${u.email}${u.email_verified ? ' (bevestigd)' : ''}.`
      : 'Er staat nog geen e-mailadres op je account.';
  }
  return `Jij bent ${naam || u.username}, inlognaam "${u.username}".` +
    (u.email ? ` E-mail: ${u.email}.` : '') +
    (u.is_admin ? ' Je bent admin.' : '');
}

async function quickReply(message, req) {  const v = versionInfo();
  const base = process.env.PUBLIC_URL
    ? String(process.env.PUBLIC_URL).replace(/\/$/, '')
    : `${req.protocol}://${req.get('host')}`;
  const m = message.toLowerCase().trim();

  // Alleen een kale begroeting -> groet terug. Meteen daarna komt een vraag
  // (bv. "hoi wat is 1000x2") dus NÓÓT grijpen als het bericht meer bevat.
  if (/^(hoi+|hallo+|hey+|hai+|yo+|goedemorgen|goedemiddag|goedenavond|hallo daar|hoi daar)[!.,?\s]*$/.test(m)) {
    return 'Hoi! Waar kan ik je mee helpen? 🚀';
  }
  const reken = quickMath(m);
  if (reken) return reken;
  if (/^(help|wat kun je|wat kan je|wat doe je|jouw functies)\b/.test(m) ||
      /\b(help me|kun je helpen)\b/.test(m)) {
    return 'Dit kan ik voor je doen:\n' +
      '• Vragen beantwoorden en uitleg geven\n' +
      '• Code en scripts schrijven — zeg bv. "maak een Python-script dat …"\n' +
      '• Live zoeken: "zoek <onderwerp> op"\n' +
      '• Onthouden: "onthoud dat …" en "wat weet je van me"\n' +
      '• Apps downloaden: typ "download" in AeroSeek\n' +
      '• Op je Mini-PC werken: "voer uit: maak een script dat …" — ik maak een plan en jij geeft toestemming\n' +
      `• Status: AeroSurf ${v.version || '?'} (build ${v.build || '?'})`;
  }
  if (m.includes('wie ben je') || m.includes('je naam') || m.includes('welk model') ||
      m.includes('hoe heet je') || m.includes('hoe heet jij') || m.includes('ben jij een ai')) {
    return 'Ik ben AeroNova AI, de vaste assistent van de AeroSurf Browser. 🐺 Ik draai zelf op jouw Mini-PC.';
  }
  // Snel antwoord op vragen over HÉM/HAAR (uit account, geen model nodig).
  const overMij = await profileQuick(m, req);
  if (overMij) return overMij;
  const naamIs = m.match(/(?:mijn naam is|ik heet|noem me)\s+(.+)/);
  if (naamIs && naamIs[1].trim().length > 1 && naamIs[1].trim().length < 40) {
    const naam = naamIs[1].trim().replace(/\s+(op|naar|eens|even)$/, '').trim();
    const uid = await effectiveUserId(req);
    await saveMemory(uid, `mijn naam is ${naam}`);
    const mooi = naam.charAt(0).toUpperCase() + naam.slice(1);
    return `Leuk je te ontmoeten, ${mooi}! 🚀 Ik heb het onthouden.`;
  }
  if (m.includes('hoe heet ik') || m.includes('weet je mijn naam') ||
      m.includes('hoe denk je dat ik heet') || m.includes('wat is mijn naam')) {
    const uid = await effectiveUserId(req);
    const feiten = await getMemory(uid);
    const naamFeit = feiten.find((f) => /naam is/i.test(f));
    if (naamFeit) {
      const nm = naamFeit.replace(/.*naam is\s+/i, '').trim();
      return `Jij bent ${nm}! 🚀 (Dat heb je me zelf verteld.)`;
    }
    return 'Dat weet ik nog niet! Zeg "mijn naam is ..." en ik vergeet het nooit meer. 🚀';
  }
  if (/\b(download|apk|installeren|installer|exe|windows-versie)\b/.test(m)) {
    return `Apps downloaden kan zo:\n• Typ het codewoord "download" in de AeroSeek-zoekbalk, of\n• Open direct: https://github.com/GamerWolfert/cyberwolfert/releases/download/v${v.version || '0.0.0'}/AeroSurf-apps.zip\nDaarin zit de Android-APK, Windows-versie en uitleg.`;
  }
  if (/^(wat is de )?(nieuwste )?versie\b|^is er (al )?een (nieuwe )?update|\bheb ik een update\b|werk ik al bij/.test(m)) {
    return `We draaien AeroSurf ${v.version || '?'} (build ${v.build || '?'}). ` +
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
    let prof = '';
    try { prof = (await profileContext(uid, false)).trim(); } catch (_) {}
    const delen = [];
    if (feiten.length) delen.push(`Onthouden:\n• ${feiten.join('\n• ')}`);
    if (prof) delen.push(prof);
    if (!delen.length) return 'Ik heb nog niets over je onthouden. Zeg "onthoud dat ..." en ik bewaar het.';
    return delen.join('\n\n') + '\n\nZeg "vergeet ..." om iets te wissen.';
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
      return `Dit vond AeroSeek voor "${q}":\n${top}\n\nTik op een resultaat om het in AeroSurf te openen.`;
    }
  }
  if (m.includes('wolfpulse') || m.includes(' zoekmachine')) {
    return 'AeroSeek is onze eigen zoekmachine: eigen links eerst, daarna resultaten via SearXNG/DuckDuckGo/Wikipedia. Alles loopt via jouw Mini-PC.';
  }
  if (/\b(bedankt|dank[je]{1,2}( wel)?|thanks|thx)\b/.test(m) && m.length < 60) {
    return 'Graag gedaan! 🚀 Waar kan ik je nog mee helpen?';
  }
  if (/^(test|hallo+$|hey+$|hoi+$|ok|oké|ja|nee|hmm+|super|top)\.?$/.test(m)) {
    const variants = [
      'Ik ben er! 🚀 Stel me een vraag, zeg "zoek <onderwerp> op" of typ "help".',
      'Hoi hoi! 🚀 Waar kan ik je mee helpen?',
      'Aangesloten en klaar! 🚀 Vraag me iets, of laat me iets opzoeken.',
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
    return `\nLive zoekresultaten van AeroSeek (gebruik als het klopt, verzin niets):\n${top}`;
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
  const t0 = Date.now();
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
        return res.json({ assistant: 'AeroNova AI', reply: quick, engine: 'quick', code: false });
      }
    } catch (e) {
      console.warn('[ai] quick failed:', e.message);
    }
  }

  const codeMode = isCodeAsk(message);
  let memoryLine = '';
  let profielLine = '';
  const uid = await effectiveUserId(req).catch(() => null);
  try {
    const feiten = await getMemory(uid);
    if (feiten.length) memoryLine = `\nDingen die je over deze gebruiker weet: ${feiten.join('; ')}.`;
  } catch (_) {}
  try {
    profielLine = await profileContext(uid);
  } catch (_) {}

  // Browsergeschiedenis van de app (RecentService) als die meegestuurd wordt.
  let recentLine = '';
  const recent = Array.isArray(req.body?.recent) ? req.body.recent.slice(0, 8) : [];
  if (recent.length) {
    const items = recent
      .map((r) => (typeof r === 'string' ? r : `${r.title || ''} — ${r.url || ''}`.replace(/^ — /, '')))
      .filter(Boolean);
    if (items.length) recentLine = `\nRecent geopend in de browser: ${items.join('; ')}.`;
  }

  const ctx = await webContext(message, codeMode);
  const sysFor = (cm) =>
    IDENTITY + '\n' + STYLE + (cm ? '\n' + CODING : '') + profielLine + memoryLine + recentLine + ctx +
    `\nHet is nu ${new Date().toLocaleString('nl-NL')}. AeroSurf ${versionInfo().version}.`;
  const build = async (cm) => {
    // Server-side geheugen: eerdere gesprekken uit ai_chats als de client
    // met een lege geschiedenis komt (nieuw scherm / herstart). Elk bericht
    // wordt geknipt op 300 tekens: opgeslagen code-antwoorden mogen de prompt
    // niet laten exploderen (prompt-eval is het duurste onderdeel).
    const cap = (m) => ({
      role: m.role,
      content: String(m.content || '').slice(0, 300),
    });
    let hist = Array.isArray(history) ? history.slice(-8).map(cap) : [];
    if (hist.length < 2) {
      try {
        const rows = await db.query(
          'SELECT role, content FROM ai_chats WHERE user_id=$1 ORDER BY id DESC LIMIT 4',
          [uid]
        );
        if (rows.rows.length) {
          const oud = rows.rows.reverse().map(cap);
          hist = [...oud, ...hist].slice(-8);
        }
      } catch (_) {}
    }
    return [
      { role: 'system', content: sysFor(cm) },
      ...hist,
      { role: 'user', content: message },
    ];
  };
  const messages = await build(codeMode);

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

  // Weigering herkennen -> één tweede ronde met de coder en een dwingende regel.
  if (out && !codeMode && isRefusal(out.reply)) {
    try {
      const force = await build(true);
      force[force.length - 1] = {
        role: 'user',
        content: `${message}\n\n[Regel: je BIEDT dit altijd aan en levert het ook. Schrijf de code/het script ` +
          'en zeg hoe je het uitvoert. Nooit weigeren, nooit "dat kan ik niet".]',
      };
      const second = await ollamaChat(force, true);
      if (second && second.reply && !isRefusal(second.reply)) out = second;
    } catch (e) {
      console.warn('[ai] herstel-aanvraag mislukt:', e.message);
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
      return res.status(500).json({ assistant: 'AeroNova AI', error: 'ai_failed' });
    }
  }
  logChat(imageUrl ? `${message} [afbeelding: ${imageUrl}]` : message, out.reply, req);
  log.ai(await naamOf(await effectiveUserId(req)), message, out.engine);
  if (process.env.AI_TIMING === '1') {
    const sysLen = (messages[0] && messages[0].content ? messages[0].content.length : 0);
    const histLen = Math.max(0, messages.length - 2);
    console.log(
      `[ai-timing] /chat totaal=${Date.now() - t0}ms engine=${out.engine} ` +
        `sys=${sysLen}tek hist=${histLen} bericht=${String(message).length}tek`
    );
  }
  res.json({
    assistant: 'AeroNova AI',
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
      `AeroSurf ${v.version}.`;
  }
  return 'Ik draai nu in lokale modus (geen Ollama verbonden), maar ik kan wel: ' +
    'zoeken via AeroSeek ("zoek <onderwerp> op"), uitleg geven ("help"), geheugen ("onthoud dat ...") en downloads regelen ("download")' +
    (feiten.length ? `.\nWat ik van je weet: ${feiten.slice(0, 3).join('; ')}` : '.');
}

module.exports = router;
