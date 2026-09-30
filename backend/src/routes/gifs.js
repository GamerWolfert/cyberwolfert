// AeroTalk GIF-bron: haalt grappige GIF's van Tenor op (geen API-key nodig).
// GET /api/gifs?q=       -> { q, results:[{id,url,title,preview}] }
// GET /api/gifs          -> trending
// Cache 10 min in geheugen; fallback: lege lijst met reden.
const express = require('express');
const router = express.Router();

const UA = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36' };
const TTL = 10 * 60 * 1000;
const cache = new Map(); // q -> { at, items }
const hits = new Map(); // ip -> { at, n }

const GIF_RE = /https:\/\/media[0-9]?\.tenor\.com\/([A-Za-z0-9_-]+)\/([a-z0-9-]+)\.gif/g;
const PREVIEW_RE = /https:\/\/media[0-9]?\.tenor\.com\/([A-Za-z0-9_-]+)\/([a-z0-9-]+)\.(?:webp|mp4)/g;

function slugify(q) {
  return String(q || '').toLowerCase().replace(/[^a-z0-9\s-]/g, '').trim().replace(/\s+/g, '-');
}

function parse(html) {
  const out = [];
  const seen = new Set();
  let m;
  GIF_RE.lastIndex = 0;
  while ((m = GIF_RE.exec(html))) {
    const id = m[1];
    if (seen.has(id)) continue;
    seen.add(id);
    out.push({
      id,
      url: `https://media.tenor.com/${id}/${m[2]}.gif`,
      preview: `https://media.tenor.com/${id}/${m[2]}.webp`,
      title: m[2].replace(/-/g, ' '),
    });
    if (out.length >= 40) break;
  }
  if (!out.length) {
    PREVIEW_RE.lastIndex = 0;
    while ((m = PREVIEW_RE.exec(html))) {
      const id = m[1];
      if (seen.has(id)) continue;
      seen.add(id);
      out.push({
        id,
        url: `https://media.tenor.com/${id}/${m[2]}.mp4`,
        preview: `https://media.tenor.com/${id}/${m[2]}.webp`,
        title: m[2].replace(/-/g, ' '),
      });
      if (out.length >= 40) break;
    }
  }
  return out;
}

function limited(ip) {
  const now = Date.now();
  const e = hits.get(ip);
  if (!e || now - e.at > 60000) {
    hits.set(ip, { at: now, n: 1 });
    return false;
  }
  e.n += 1;
  return e.n > 40;
}

router.get('/', async (req, res) => {
  const q = String(req.query.q || '').slice(0, 60).trim();
  if (limited(req.ip)) return res.status(429).json({ error: 'te veel verzoeken', results: [] });

  const key = q.toLowerCase();
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < TTL) {
    return res.json({ q, cached: true, results: hit.items });
  }

  const url = q ? `https://tenor.com/search/${slugify(q)}-gifs` : 'https://tenor.com/';
  try {
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), 9000);
    const r = await fetch(url, { headers: UA, signal: ctl.signal, redirect: 'follow' });
    clearTimeout(t);
    const html = await r.text();
    const items = r.ok ? parse(html) : [];
    if (items.length) cache.set(key, { at: Date.now(), items });
    res.json({ q, source: 'tenor', results: items });
  } catch (e) {
    const prev = cache.get(key);
    if (prev) return res.json({ q, cached: true, results: prev.items });
    console.warn('[gifs] mislukt:', e.message);
    res.status(200).json({ q, error: 'gif-bron onbereikbaar', results: [] });
  }
});

module.exports = router;
