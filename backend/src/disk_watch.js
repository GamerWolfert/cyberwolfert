// Schijfwacht: mailt de beheerders zodra de root-schijf (bijna) vol is.
// We hadden al een crisis gehad waarbij PostgreSQL crashte op "geen ruimte
// meer" — dit is de vroeg-waarschuwing daarvoor.
const fs = require('fs');
const path = require('path');
const { sendMail, brief, baseUrl } = require('./mail');
const { RECIPIENTS } = require('./url_watch');

const STATE_FILE = path.join(__dirname, '..', 'disk_alert.json');
const THRESH = Number(process.env.DISK_ALERT_PCT || 85);
const COOLDOWN_MS = 12 * 60 * 60 * 1000; // max 1 waarschuwing per 12 uur

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

function lastAlert() {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')).at || 0;
  } catch (_) {
    return 0;
  }
}

function markAlert() {
  try {
    fs.writeFileSync(STATE_FILE, JSON.stringify({ at: Date.now() }));
  } catch (_) {}
}

function grootsteSlots() {
  try {
    const dir = '/var/opt/minecraft/crafty/crafty-4/backups';
    const names = fs.readdirSync(dir).filter((n) => n.endsWith('.zip'));
    const tot = names.reduce((a, n) => {
      try {
        return a + fs.statSync(path.join(dir, n)).size;
      } catch (_) {
        return a;
      }
    }, 0);
    return { count: names.length, gb: Math.round(tot / 1e9) };
  } catch (_) {
    return null;
  }
}

async function checkDisk(force = false) {
  const d = diskInfo();
  if (!d) return null;
  const vol = d.usedPct >= THRESH || d.freeGb <= 30;
  if (!vol) return d;
  if (!force && Date.now() - lastAlert() < COOLDOWN_MS) return d;

  const bak = grootsteSlots();
  const html = `<p>De root-schijf van de Mini-PC is bijna vol. Zonder actie kan
PostgreSQL of de backend opnieuw vastlopen (dat is al eens gebeurd).</p>
<p style="font-family:monospace;font-size:15px;">
Gebruikt: <b>${d.usedPct}%</b> &nbsp;·&nbsp; Vrij: <b>${d.freeGb} GB</b> van ${d.totalGb} GB
${bak ? `<br>Crafty-backups: ${bak.count} bestanden (${bak.gb} GB) — dit groeit elke dag.` : ''}
</p>
<p style="font-size:13px;color:#5A6779;">Controle om ${new Date().toLocaleString('nl-NL')}</p>`;

  const results = [];
  for (const to of RECIPIENTS) {
    try {
      const r = await sendMail(
        to,
        `AeroSurf waarschuwing — schijf ${d.usedPct}% vol`,
        brief({
          titel: 'Schijf bijna vol',
          intro:
            'Dit is een automatische waarschuwing van AeroSurf. Er is actie nodig voordat de schijf helemaal volloopt.',
          bodyHtml: html,
          actieUrl: `${baseUrl()}/api/health`,
          actieTekst: 'Bekijk de systeemstatus',
          slot: 'Ruim op of maak minder backups — daarna verdwijnt deze waarschuwing vanzelf.<br><br>Met vriendelijke groet,<br><b>AeroSurf</b>',
        })
      );
      results.push(`${to}: ${r && r.sent ? 'verzonden' : (r && r.reason) || 'overgeslagen'}`);
    } catch (e) {
      results.push(`${to}: fout ${e.message}`);
    }
  }
  markAlert();
  console.warn(`[disk-watch] schijf ${d.usedPct}% vol -> waarschuwing verstuurd (${results.join('; ')})`);
  return d;
}

function startDiskWatch() {
  setInterval(() => {
    checkDisk().catch((e) => console.warn('[disk-watch]', e.message));
  }, 60 * 60 * 1000).unref?.();
  setTimeout(() => {
    checkDisk().catch((e) => console.warn('[disk-watch]', e.message));
  }, 60 * 1000).unref?.();
  console.log(
    `[disk-watch] actief (drempel ${THRESH}%, cooldown 12u), nu ${JSON.stringify(diskInfo())}`
  );
}

module.exports = { startDiskWatch, checkDisk, diskInfo };
