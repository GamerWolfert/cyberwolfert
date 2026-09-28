// WolfPulse zoekproxy: eigen links eerst, daarna wereldwijde resultaten.
// Werkt ALTIJD: DB optioneel, keten SearXNG -> Bing -> DuckDuckGo Lite -> Wikipedia.
const express = require('express');
const path = require('path');
const fs = require('fs');
const db = require('../db');
const { log, naamOf } = require('../discord');
const { effectiveUserId } = require('../auth');
const router = express.Router();

const UA = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) CyberWolfertBrowser/1.8' };

async function fetchTimeout(url, opts = {}, ms = 9000) {
  const c = new AbortController();
  const t = setTimeout(() => c.abort(), ms);
  try {
    return await fetch(url, { ...opts, signal: c.signal });
  } finally {
    clearTimeout(t);
  }
}

function decodeEntities(s) {
  return String(s || '')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#x27;|&apos;/g, "'")
    .replace(/<[^>]*>/g, '').trim();
}

async function ddgLite(q) {
  try {
    const r = await fetchTimeout(
      `https://lite.duckduckgo.com/lite/?q=${encodeURIComponent(q)}`,
      { headers: { ...UA, Accept: 'text/html' } },
      6000
    );
    if (!r.ok) return [];
    const html = await r.text();
    const out = [];
    const linkRe = /<a[^>]*rel="nofollow"[^>]*href="([^"]+)"[^>]*>(.*?)<\/a>/gis;
    const snipRe = /class=['"]snippet['"][^>]*>(.*?)<\/td>/is;
    let m;
    while ((m = linkRe.exec(html)) && out.length < 10) {
      const url = m[1];
      if (url.startsWith('//duckduckgo.com') || url.includes('duckduckgo.com/y.js')) continue;
      const title = decodeEntities(m[2]);
      if (!title || !/^https?:\/\//.test(url)) continue;
      const tail = html.slice(m.index, m.index + 3000);
      const sn = snipRe.exec(tail);
      out.push({ title, url, snippet: decodeEntities(sn ? sn[1] : ''), source: 'duckduckgo' });
    }
    return out;
  } catch (e) {
    console.warn('[search] ddg failed:', e.message);
    return [];
  }
}

async function wikipedia(q) {
  for (const lang of ['nl', 'en']) {
    try {
      const r = await fetchTimeout(
        `https://${lang}.wikipedia.org/w/api.php?action=opensearch&search=${encodeURIComponent(q)}&limit=5&format=json`,
        { headers: { ...UA, Accept: 'application/json' } }
      );
      if (!r.ok) continue;
      const j = await r.json();
      const out = (j[1] || []).map((t, i) => ({
        title: `${t} — Wikipedia`,
        url: (j[3] || [])[i] || '',
        snippet: (j[2] || [])[i] || '',
        source: 'wikipedia',
      })).filter((x) => x.url);
      if (out.length) return out;
    } catch (e) {
      console.warn('[search] wiki failed:', e.message);
    }
  }
  return [];
}

async function searxInstance(base, q) {
  try {
    const sep = base.includes('?') ? '&' : '?';
    const r = await fetchTimeout(`${base}${sep}q=${encodeURIComponent(q)}&format=json`, {
      headers: { Accept: 'application/json' },
    }, 7000);
    if (!r.ok) return [];
    const j = await r.json();
    return (j.results || []).slice(0, 15).map((x) => ({
      title: x.title, url: x.url,
      snippet: x.content || x.snippet || '', source: 'searxng',
    }));
  } catch (e) {
    return [];
  }
}

// Gratis publieke SearXNG-instanties (roteren tot er een werkt, geen key nodig)
const PUBLIC_SEARX = [
  'https://searx.be/search',
  'https://search.rhscz.eu/search',
  'https://opnxng.xyz/search',
];

async function braveSearch(q) {
  if (!process.env.BRAVE_API_KEY) return [];
  try {
    const r = await fetchTimeout(
      `https://api.search.brave.com/res/v1/web/search?q=${encodeURIComponent(q)}&count=15&text_decorations=0&search_lang=nl`,
      { headers: { Accept: 'application/json', 'X-Subscription-Token': process.env.BRAVE_API_KEY } },
      8000
    );
    if (!r.ok) return [];
    const j = await r.json();
    return ((j.web && j.web.results) || []).map((x) => ({
      title: x.title, url: x.url, snippet: x.description || '', source: 'brave',
    }));
  } catch (e) {
    console.warn('[search] brave failed:', e.message);
    return [];
  }
}

async function globalSearch(q) {
  // 1) Eigen SearXNG op Mini-PC
  if (process.env.SEARXNG_URL) {
    const own = await searxInstance(process.env.SEARXNG_URL, q);
    if (own.length) return own;
  }
  // 2) Brave API (gratis tier, key in config.env) + eigen SearXNG parallel
  const [brave, ...publics] = await Promise.all([
    braveSearch(q),
    ...PUBLIC_SEARX.map((u) => searxInstance(u, q)),
  ]);
  const best = brave.length ? brave : publics.find((r) => r.length) || [];
  if (best.length) return best;
  if (process.env.BING_API_KEY) {
    try {
      const r = await fetchTimeout(
        `${process.env.BING_ENDPOINT}?q=${encodeURIComponent(q)}&count=15&mkt=nl-NL`,
        { headers: { 'Ocp-Apim-Subscription-Key': process.env.BING_API_KEY } }
      );
      const j = await r.json();
      const results = (j.webPages?.value || []).map((x) => ({
        title: x.name, url: x.url, snippet: x.snippet, source: 'bing',
      }));
      if (results.length) return results;
    } catch (e) {
      console.warn('[search] bing failed:', e.message);
    }
  }
  const [ddg, wiki] = await Promise.all([ddgLite(q), wikipedia(q)]);
  return [...ddg, ...wiki];
}

function fileLinks(q, req) {
  try {
    const f = path.join(__dirname, '..', '..', 'custom_links.json');
    if (!fs.existsSync(f)) return [];
    const base = process.env.PUBLIC_URL
      ? String(process.env.PUBLIC_URL).replace(/\/$/, '')
      : `${req.protocol}://${req.get('host')}`;
    const all = JSON.parse(fs.readFileSync(f, 'utf8'));
    const ql = q.toLowerCase();
    return all
      .filter((l) => l.keyword && ql.includes(String(l.keyword).toLowerCase()))
      .sort((a, b) => (b.priority || 0) - (a.priority || 0))
      .slice(0, 5)
      .map((l) => ({
        title: l.title,
        url: String(l.url).startsWith('/') ? base + l.url : l.url,
        snippet: l.description || '',
        source: 'local',
      }));
  } catch {
    return [];
  }
}

async function dbLinks(q, req) {
  try {
    const uid = await effectiveUserId(req);
    if (!uid) return { uid: null, local: [] };
    try {
      await db.query('INSERT INTO search_history (user_id, query) VALUES ($1,$2)', [uid, q]);
    } catch (_) {}
    const lr = await db.query(
      `SELECT title, url, description AS snippet, 'local' AS source, priority
       FROM custom_links WHERE user_id=$1 AND $2 ILIKE '%'||keyword||'%'
       ORDER BY priority DESC LIMIT 5`,
      [uid, q]
    );
    return { uid, local: lr.rows };
  } catch {
    return { uid: null, local: [] };
  }
}

router.get('/', async (req, res) => {
  const q = (req.query.q || '').trim();
  if (!q) return res.status(400).json({ error: 'missing_q' });
  const { local: dbLocal, uid } = await dbLinks(q, req);
  if (uid) log.zoekterm(await naamOf(uid), q);
  const local = [...dbLocal, ...fileLinks(q, req)];
  const global = await globalSearch(q);
  res.json({ query: q, local, results: [...local, ...global] });
});

router.get('/history', async (req, res) => {
  try {
    const uid = await effectiveUserId(req);
    if (!uid) return res.json([]);
    const r = await db.query(
      `SELECT query, created_at FROM search_history
       WHERE user_id=$1 ORDER BY created_at DESC LIMIT 50`,
      [uid]
    );
    res.json(r.rows);
  } catch {
    res.json([]);
  }
});

router.post('/links', async (req, res) => {
  const { keyword, title, url, description, priority } = req.body;
  if (!keyword || !title || !url) return res.status(400).json({ error: 'missing_fields' });
  try {
    const uid = await effectiveUserId(req);
    if (!uid) throw new Error('no db');
    const r = await db.query(
      'INSERT INTO custom_links (user_id,keyword,title,url,description,priority) VALUES ($1,$2,$3,$4,$5,$6) RETURNING *',
      [uid, keyword, title, url, description || '', priority || 100]
    );
    res.json(r.rows[0]);
  } catch {
    const f = path.join(__dirname, '..', '..', 'custom_links.json');
    const all = fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : [];
    const row = { keyword, title, url, description: description || '', priority: priority || 100 };
    all.push(row);
    fs.writeFileSync(f, JSON.stringify(all, null, 2));
    res.json({ ...row, source: 'file' });
  }
});

module.exports = router;
module.exports.globalSearch = globalSearch;
