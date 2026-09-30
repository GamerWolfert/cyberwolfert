// Officiele melding bij wijziging van de publieke website-URL.
// De quick-tunnel (cloudflared) levert elke herstart een nieuwe URL aan via
// backend/tunnel.json (door tunnel-watch.sh weggeschreven). Zodra die URL
// (of PUBLIC_URL) anders is dan de laatst-gekende waarde, krijgen de
// beheerders per mail de nieuwe URL.
const fs = require('fs');
const path = require('path');
const { mails } = require('./mail');

const RECIPIENTS = [
  '130186@denieuweveste.nl',
  'wolfertvl@gmail.com',
  'gamerwolfertyt@gmail.com',
  '130521@denieuweveste.nl',
  '130499@denieuweveste.nl',
];

const STATE_FILE = path.join(__dirname, '..', 'url_last.txt');
const TUNNEL_FILE = path.join(__dirname, '..', 'tunnel.json');

function currentUrl() {
  try {
    const j = JSON.parse(fs.readFileSync(TUNNEL_FILE, 'utf8'));
    if (j && j.url) return String(j.url).replace(/\/$/, '');
  } catch (_) {}
  if (process.env.PUBLIC_URL) return String(process.env.PUBLIC_URL).replace(/\/$/, '');
  return null;
}

function readLast() {
  try {
    return fs.readFileSync(STATE_FILE, 'utf8').trim() || null;
  } catch (_) {
    return null;
  }
}

function writeLast(url) {
  try {
    fs.writeFileSync(STATE_FILE, url ? url + '\n' : '');
  } catch (e) {
    console.warn('[url-watch] state wegschrijven mislukt:', e.message);
  }
}

// Eerste bekende URL alleen onthouden (geen mail), daarna bij elk verschil
// de officiele melding sturen. Mailfouten mogen de watcher nooit laten crashen.
async function checkUrlChange() {
  const url = currentUrl();
  if (!url) return;
  const last = readLast();
  if (last === url) return;
  if (!last) {
    writeLast(url);
    console.log(`[url-watch] bekende URL vastgelegd: ${url}`);
    return;
  }
  writeLast(url);
  console.log(`[url-watch] URL gewijzigd: ${last} -> ${url} — officiele melding sturen`);
  for (const to of RECIPIENTS) {
    try {
      const r = await mails.urlGewijzigd(to, last, url);
      if (!r || !r.sent) console.warn(`[url-watch] mail naar ${to} niet bezorgd:`, r && r.reason);
    } catch (e) {
      console.warn(`[url-watch] mail naar ${to} mislukt:`, e.message);
    }
  }
}

function startUrlWatch(intervalMs = 20000) {
  const tick = setInterval(() => {
    checkUrlChange().catch((e) => console.warn('[url-watch]', e.message));
  }, intervalMs);
  if (tick.unref) tick.unref();
  // Direct bij start controleren (publiceert meteen de huidige waarde).
  setTimeout(() => checkUrlChange().catch(() => {}), 4000).unref?.();
  console.log('[url-watch] controle op URL-wijziging actief');
}

module.exports = { startUrlWatch, checkUrlChange, RECIPIENTS };
