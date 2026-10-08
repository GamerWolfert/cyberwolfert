// AeroSurf page-proxy: sites die iframes weigeren toch BINNEN de browser.
// GET /api/frame-check?url=... -> { framing: 'open'|'blocked'|'na' }
// GET /api/proxy?url=... -> pagina zonder framing-headers (alleen text/html)
// SSRF-guard: alleen publieke http(s), geen LAN/loopback, poort 80/443, max 3MB.
const express = require('express');
const dns = require('dns').promises;
const router = express.Router();

const UA = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) CyberWolfertBrowser/1.8' };

function isPrivateIp(ip) {
  if (!ip) return true;
  if (ip.includes(':')) return true;
  const p = ip.split('.').map(Number);
  if (p.length !== 4 || p.some((n) => Number.isNaN(n))) return true;
  const [a, b] = p;
  return (
    a === 10 || a === 127 || (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) ||
    a === 0 || a >= 224
  );
}

async function checkUrl(raw) {
  let u;
  try {
    u = new URL(raw);
  } catch {
    return { ok: false, error: 'ongeldige url' };
  }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return { ok: false, error: 'alleen http(s)' };
  if (u.port && u.port !== '80' && u.port !== '443') return { ok: false, error: 'poort geblokkeerd' };
  if (/^(localhost|.*\.localhost|.*\.local|.*\.lan|.*\.home)$/i.test(u.hostname)) {
    return { ok: false, error: 'lokaal geblokkeerd' };
  }
  try {
    const addrs = await dns.lookup(u.hostname, { all: true });
    if (!addrs.length || addrs.some((a) => isPrivateIp(a.address))) {
      return { ok: false, error: 'prive-adres geblokkeerd' };
    }
  } catch {
    return { ok: false, error: 'domein niet gevonden' };
  }
  return { ok: true, url: u.toString() };
}

function friendlyReason(msg) {
  const m = (msg || '').toLowerCase();
  if (m.includes('ongeldige')) return 'Dit is geen geldig webadres. Typ bijvoorbeeld google.com of https://site.nl';
  if (m.includes('poort') || m.includes('lokaal') || m.includes('prive')) {
    return 'Deze site kan alleen binnen je eigen netwerk (lokaal/LAN), niet via de proxy.';
  }
  if (m.includes('domein niet gevonden')) return 'Domein niet gevonden — controleer de spelling van het adres.';
  if (m.includes('alleen http')) return 'Alleen http:// en https:// adressen werken in AeroSurf.';
  return 'Deze pagina is niet bereikbaar.';
}

// frame-check: BEOORDEEL of een adres bruikbaar is (voor de browser).
// Alles wordt toegestaan, ook LAN-adressen, poorten en localhost — daar
// deed de vorige versie te streng over en dan weigerde AeroSurf geldige URL's.
router.get('/frame-check', async (req, res) => {
  const raw = req.query.url || '';
  let u;
  try {
    u = new URL(raw);
  } catch {
    return res.json({ framing: 'na', reason: friendlyReason('ongeldige url') });
  }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') {
    return res.json({ framing: 'na', reason: friendlyReason('alleen http') });
  }
  try {
    await dns.lookup(u.hostname);
  } catch {
    return res.json({ framing: 'na', reason: friendlyReason('domein niet gevonden') });
  }
  try {
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), 8000);
    const r = await fetch(u.toString(), { headers: UA, signal: ctl.signal, redirect: 'follow' });
    clearTimeout(t);
    const xfo = (r.headers.get('x-frame-options') || '').toLowerCase();
    const csp = (r.headers.get('content-security-policy') || '').toLowerCase();
    const blocked =
      xfo.includes('deny') || xfo.includes('sameorigin') ||
      /frame-ancestors[^;]*('none'|[^;]*'self')/.test(csp);
    if (!blocked) return res.json({ framing: 'open', status: r.status });
    // Framing geblokkeerd: alleen echt verder helpen als de proxy mag.
    const proxyOk = await checkUrl(u.toString());
    if (!proxyOk.ok) {
      return res.json({ framing: 'na', reason: friendlyReason(proxyOk.error), status: r.status });
    }
    return res.json({ framing: 'blocked', status: r.status });
  } catch (e) {
    const reason =
      e && e.name === 'AbortError'
        ? 'Deze site reageert niet (timeout).'
        : 'Verbinding met deze site mislukt — hij is nu niet bereikbaar.';
    return res.json({ framing: 'na', reason });
  }
});

router.get('/proxy', async (req, res) => {
  const c = await checkUrl(req.query.url || '');
  if (!c.ok) return res.status(400).json({ error: c.error });
  try {
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), 15000);
    const r = await fetch(c.url, { headers: { ...UA, Accept: 'text/html' }, signal: ctl.signal });
    clearTimeout(t);
    const type = (r.headers.get('content-type') || '').toLowerCase();
    if (!r.ok) return res.status(502).json({ error: `bron gaf ${r.status}` });
    if (!type.includes('text/html')) {
      return res.status(415).json({ error: 'geen webpagina (alleen html via proxy)' });
    }
    let html = await r.text();
    if (html.length > 3 * 1024 * 1024) return res.status(413).json({ error: 'pagina te groot' });
    html = html.replace(/<meta[^>]*http-equiv=["']?Content-Security-Policy["']?[^>]*>/gi, '');
    const base = `<base href="${c.url}">`;
    if (/<head[^>]*>/i.test(html)) {
      html = html.replace(/<head([^>]*)>/i, `<head$1>${base}`);
    } else {
      html = base + html;
    }
    html = html.replace(/<body([^>]*)>/i, '<body$1><!-- via AeroSurf proxy -->');
    res.set('Content-Type', 'text/html; charset=utf-8');
    res.set('Cache-Control', 'no-store');
    res.send(html);
  } catch (e) {
    res.status(504).json({ error: 'proxy_timeout' });
  }
});

module.exports = router;
