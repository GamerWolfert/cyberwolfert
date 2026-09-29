// Remote agent: AI stelt een plan op -> jij keurt het goed -> de Mini-PC voert het uit.
// Veiligheid: alleen ingelogde gebruikers met 'agent.run' (admin), relatieve paden,
// commando-whitelist, 20s timeout, alles binnen ~/wolf-agent/<user>/.
const express = require('express');
const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const { execFile } = require('child_process');
const db = require('../db');
const { authRequired } = require('../auth');
const { effectivePerms } = require('../perms');
const { log } = require('../discord');
const router = express.Router();

const ALLOWED = [
  'python3', 'python', 'node', 'bash', 'ls', 'cat', 'echo', 'mkdir', 'pwd',
  'head', 'tail', 'wc', 'touch', 'date',
  'grep', 'find', 'sort', 'uniq', 'cut', 'stat', 'du', 'df', 'file', 'which',
  'whoami', 'basename', 'dirname', 'seq', 'tr', 'nl', 'id', 'uname',
];
// Commando's die iets mogen schrijven: alleen RELATIEVE paden in de werkmap.
const WRITE_BINS = new Set(['python3', 'python', 'node', 'bash', 'echo', 'mkdir', 'touch']);
const MAX_STEPS = 6;
const MAX_FILE = 60 * 1024;
const CMD_TIMEOUT = 20000;
const PLAN_TTL = 10 * 60 * 1000;
const PLANS = new Map();

router.use(authRequired);

async function agentGate(req, res, next) {
  try {
    const perms = await effectivePerms(db, req.userId);
    if (!perms['agent.run']) return res.status(403).json({ error: 'geen_toestemming' });
    req.perms = perms;
    next();
  } catch (e) {
    res.status(500).json({ error: 'gate_failed' });
  }
}

function workdirFor(uid) {
  return path.join(os.homedir(), 'wolf-agent', `user${uid}`);
}

function fetchTimeout(url, opts = {}, ms) {
  const c = new AbortController();
  const t = setTimeout(() => c.abort(), ms);
  return fetch(url, { ...opts, signal: c.signal }).finally(() => clearTimeout(t));
}

function plannerPrompt(goal) {
  return `Je bent de plan-module van de CyberWolfert-agent op een Fedora Mini-PC.
De gebruiker geeft straks toestemming; jij levert alleen een plan.

Antwoord ALLEEN met geldige JSON (geen tekst eromheen, geen uitleg):
{"summary":"korte NL samenvatting van wat je gaat doen","steps":[
  {"type":"file","path":"relatief/bestand.py","content":"volledige inhoud"},
  {"type":"cmd","cmd":"python3 relatief/bestand.py"}
]}

Regels:
- Alleen JSON. Geen markdown, geen comments.
- 1 tot ${MAX_STEPS} stappen.
- Paden RELATIEF (nooit beginnen met /, nooit .. bevatten), bestanden komen in de werkmap.
- cmd mag alleen starten met: ${ALLOWED.join(', ')}.
- Geen pipes (|), geen ;, geen &&, geen redirect (> <), geen $ of backticks.
- Zoeken, filteren of tellen mag met de leescommando's (ls, grep, find, wc, head,
  tail, stat, du) — maar dan ZONDER pipe — of met een python3-script:
  maak het bestand met type "file" en draai het met "python3 <pad>".
- Schrijvende commando's (python3, node, bash, echo, mkdir, touch) gebruiken
  ALLEEN relatieve paden in de werkmap. Leescommando's mogen ook absolute paden
  gebruiken, bijv. "ls /home/wolfert/cyberwolfert/backend".
- Een bestand aanmaken doe je ALTIJD met een stap van type "file" (pad + content),
  NOOIT met echo/printf en een >-teken — dat wordt geweigerd.
  Voorbeeld: {"summary":"Maakt test.txt","steps":[{"type":"file","path":"test.txt","content":"hallo wereld"},{"type":"cmd","cmd":"cat test.txt"}]}
- Schrijf werkende, complete code (python3/node/bash).
- GEEN tests, geen asserts, geen self-checks in het script: alleen doen wat de gebruiker vroeg.
- Gebruik geen interactieve input (input()/prompt), want het script draait automatisch.
- Als je informatie mist: maak een aanname en zet die in summary.
- Gebruikersdoel: ${JSON.stringify(String(goal).slice(0, 1200))}`;
}

function looseJson(text) {
  if (!text) return null;
  let t = String(text).trim();
  t = t.replace(/^```(?:json)?/i, '').replace(/```\s*$/i, '').trim();
  const a = t.indexOf('{');
  const b = t.lastIndexOf('}');
  if (a < 0 || b <= a) return null;
  try {
    return JSON.parse(t.slice(a, b + 1));
  } catch {
    return null;
  }
}

async function askPlanner(goal, hint) {
  const model = process.env.AI_CODE_MODEL || 'qwen2.5-coder:3b';
  let u = process.env.OLLAMA_URL || 'http://127.0.0.1:11434/api/chat';
  if (!/\/api\/chat$/.test(u)) u = u.replace(/\/$/, '') + '/api/chat';
  const sys = plannerPrompt(goal) +
    (hint
      ? `\nJE VORIGE PLAN IS AFGEKEURD: ${hint}\n` +
        'Je mag ALLEEN deze commando\'s gebruiken en GEEN pipes/redirects/;/$/` : ' +
        `${ALLOWED.join(', ')}. ` +
        'Zonder pipe kun je tellen/filteren met een python3-script: maak het ' +
        'bestand (type "file") en draai het met "python3 <pad>".\n' +
        'Lever opnieuw ALLEEN geldige JSON die dit probleem oplost.'
      : '');
  const r = await fetchTimeout(u, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model,
      stream: false,
      format: 'json', // dwingt geldige JSON af bij Ollama
      messages: [
        { role: 'system', content: sys },
        { role: 'user', content: goal },
      ],
      options: { num_predict: 1200, temperature: 0.1, top_p: 0.9, num_ctx: 4096, repeat_penalty: 1.02, keep_alive: '15m' },
    }),
  }, 90000);
  if (!r.ok) throw new Error(`ollama http ${r.status}`);
  const j = await r.json();
  return j.message?.content || j.response || '';
}

function badPath(p) {
  const s = String(p || '').trim();
  if (!s) return true;
  if (s.startsWith('/') || s.startsWith('~') || s.includes('\\')) return true;
  if (s.split('/').some((seg) => seg === '..' || seg === '')) return true;
  if (!/^[A-Za-z0-9._\-/]+$/.test(s)) return true;
  return false;
}

function badCmd(c) {
  const s = String(c || '').trim();
  if (!s || s.length > 400) return true;
  // geen shell-magic: pipes, redirects, sleepjes, variabelen of subshell
  if (/[;&`$><|]/.test(s)) return true;
  if (s.includes('..')) return true;
  const toks = s.split(/\s+/);
  const bin = toks[0];
  if (!ALLOWED.includes(bin)) return true;
  // schrijvende commando's blijven binnen de eigen werkmap
  if (WRITE_BINS.has(bin) && toks.slice(1).some((t) => t.startsWith('/') || t.startsWith('~'))) {
    return true;
  }
  return false;
}

function validate(raw, goal) {
  const p = typeof raw === 'string' ? looseJson(raw) : raw;
  if (!p || typeof p !== 'object') return { error: 'geen JSON-plan' };
  const summary = String(p.summary || '').slice(0, 300).trim() || 'Plan';
  const steps = Array.isArray(p.steps) ? p.steps : [];
  if (!steps.length || steps.length > MAX_STEPS) return { error: `aantal stappen moet 1-${MAX_STEPS} zijn` };
  const out = [];
  for (const s of steps) {
    if (!s || typeof s !== 'object') return { error: 'stap is geen object' };
    if (s.type === 'file') {
      if (badPath(s.path)) return { error: `ongeldig pad: ${String(s.path).slice(0, 60)}` };
      const content = typeof s.content === 'string' ? s.content : '';
      if (!content) return { error: `leeg bestand: ${s.path}` };
      if (Buffer.byteLength(content) > MAX_FILE) return { error: `bestand te groot: ${s.path}` };
      out.push({ type: 'file', path: s.path, content });
    } else if (s.type === 'cmd') {
      if (badCmd(s.cmd)) return { error: `niet-toegestaan commando: ${String(s.cmd).slice(0, 80)}` };
      out.push({ type: 'cmd', cmd: String(s.cmd).trim() });
    } else {
      return { error: `onbekend steptype: ${String(s.type).slice(0, 40)}` };
    }
  }
  return { id: crypto.randomUUID(), goal: String(goal).slice(0, 1200), summary, steps: out };
}

router.get('/status', (req, res) => {
  res.json({
    allowed: true,
    model: process.env.AI_CODE_MODEL || 'qwen2.5-coder:3b',
    allowedCmds: ALLOWED,
    timeoutSec: CMD_TIMEOUT / 1000,
    workdir: `~/wolf-agent/user${req.userId}`,
    pending: [...PLANS.values()].filter((p) => p.uid === req.userId).length,
  });
});

router.post('/plan', agentGate, async (req, res) => {
  const goal = String(req.body?.goal || '').trim();
  if (goal.length < 3) return res.status(400).json({ error: 'doel ontbreekt' });
  let raw;
  try {
    raw = await askPlanner(goal, '');
  } catch (e) {
    return res.status(502).json({ error: 'planner_offline', detail: String(e.message || e).slice(0, 200) });
  }
  let plan = validate(raw, goal);
  if (plan.error) {
    try {
      const raw2 = await askPlanner(goal, plan.error);
      const plan2 = validate(raw2, goal);
      if (!plan2.error) {
        plan = plan2;
        raw = raw2;
      } else {
        plan = plan2;
      }
    } catch (_) {}
  }
  if (plan.error) return res.status(422).json({ error: plan.error, raw: String(raw).slice(0, 600) });
  plan.uid = req.userId;
  plan.createdAt = Date.now();
  plan.workdir = workdirFor(req.userId);
  PLANS.set(plan.id, plan);
  for (const [k, v] of PLANS) if (Date.now() - v.createdAt > PLAN_TTL) PLANS.delete(k);
  res.json({ id: plan.id, summary: plan.summary, steps: plan.steps.map(({ content, ...s }) => s), workdir: plan.workdir });
});

function runCmd(cmd, cwd) {
  return new Promise((resolve) => {
    const parts = cmd.split(/\s+/);
    const bin = parts[0];
    const args = parts.slice(1);
    execFile(bin, args, {
      cwd,
      timeout: CMD_TIMEOUT,
      maxBuffer: 200 * 1024,
      env: { PATH: process.env.PATH, HOME: process.env.HOME, LANG: 'C.UTF-8', LC_ALL: 'C.UTF-8' },
    }, (err, stdout, stderr) => {
      resolve({
        code: err ? (err.code === 'ENOENT' ? 127 : err.killed ? 124 : 1) : 0,
        out: String(stdout || '').slice(0, 4000),
        err: String(stderr || err?.message || '').slice(0, 2000),
      });
    });
  });
}

router.post('/run', agentGate, async (req, res) => {
  const plan = PLANS.get(String(req.body?.id || ''));
  if (!plan) return res.status(404).json({ error: 'plan_vervallen', hint: 'vraag een nieuw plan aan' });
  if (plan.uid !== req.userId) return res.status(403).json({ error: 'plan_van_andere' });
  PLANS.delete(plan.id);

  const cwd = plan.workdir;
  try {
    fs.mkdirSync(cwd, { recursive: true });
  } catch (e) {
    return res.status(500).json({ error: 'werkmap_maken_mislukt' });
  }

  const results = [];
  for (let i = 0; i < plan.steps.length; i++) {
    const s = plan.steps[i];
    if (s.type === 'file') {
      const full = path.resolve(cwd, s.path);
      if (!full.startsWith(path.resolve(cwd) + path.sep)) {
        results.push({ step: i + 1, type: 'file', path: s.path, ok: false, out: '', err: 'pad buiten werkmap' });
        break;
      }
      try {
        fs.mkdirSync(path.dirname(full), { recursive: true });
        fs.writeFileSync(full, s.content, 'utf8');
        results.push({ step: i + 1, type: 'file', path: s.path, ok: true, out: `geschreven (${Buffer.byteLength(s.content)} bytes)`, err: '' });
      } catch (e) {
        results.push({ step: i + 1, type: 'file', path: s.path, ok: false, out: '', err: String(e.message).slice(0, 500) });
        break;
      }
    } else {
      const r = await runCmd(s.cmd, cwd);
      results.push({ step: i + 1, type: 'cmd', cmd: s.cmd, ok: r.code === 0, code: r.code, out: r.out, err: r.err });
      if (r.code !== 0) break;
    }
  }

  const okCount = results.filter((r) => r.ok).length;
  log.wolfsyn(`\`[${new Date().toISOString().replace('T', ' ').slice(0, 19)}]\` **agent** door \`user#${plan.uid}\`: ${plan.goal.slice(0, 400)} -> ${okCount}/${plan.steps.length} stappen ok`);
  res.json({ ok: okCount === plan.steps.length, workdir: cwd, summary: plan.summary, results });
});

module.exports = router;
