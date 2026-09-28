// CyberWolfert Mail: officiele e-mails in huisstijl (logo, banner, formele brief).
// Werkt lokaal op de Mini-PC en bezorgt via een SMTP-relay naar het open
// netwerk (Gmail/Brevo-gratis). Een volledig eigen SMTP-server vanaf een
// thuisnetwerk levert vrijwel niets af (geen PTR/reputatie, poort 25 dicht),
// daarom: eigen afzender-naam + relay. Config via config.env (MAIL_*).
const nodemailer = require('nodemailer');

let transporter = null;

function getTransporter() {
  if (transporter) return transporter;
  const host = process.env.MAIL_HOST;
  if (!host) return null;
  transporter = nodemailer.createTransport({
    host,
    port: Number(process.env.MAIL_PORT || 587),
    secure: String(process.env.MAIL_SECURE || 'false') === 'true',
    auth: process.env.MAIL_USER
      ? { user: process.env.MAIL_USER, pass: process.env.MAIL_PASS || '' }
      : undefined,
  });
  return transporter;
}

function fromLine() {
  const name = process.env.MAIL_FROM_NAME || 'CyberWolfert Team';
  const addr = process.env.MAIL_FROM || 'no-reply@cyberwolfert.local';
  return `"${name}" <${addr}>`;
}

function baseUrl() {
  return (process.env.PUBLIC_URL || `http://192.168.1.42:${process.env.PORT || 43711}`).replace(/\/$/, '');
}

// Officiele brief-layout: banner, logo-tekst, inhoud, groet, footer.
function brief({ titel, intro, bodyHtml, actieUrl, actieTekst, slot }) {
  return `<!DOCTYPE html><html lang="nl"><head><meta charset="utf-8"></head>
<body style="margin:0;background:#040912;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#040912;padding:24px 0;">
<tr><td align="center">
<table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;">
<tr><td style="background:linear-gradient(135deg,#0B1E42,#061224);border:1px solid #29B6F6;border-radius:12px 12px 0 0;padding:28px;text-align:center;">
<div style="font-size:42px;">🐺</div>
<div style="color:#fff;font-size:26px;font-weight:900;font-style:italic;letter-spacing:2px;">WOLF<span style="color:#29B6F6;">PULSE</span></div>
<div style="color:#9FB3C8;font-size:12px;">CyberWolfert Browser</div>
</td></tr>
<tr><td style="background:#0A1428;color:#E8EEF6;padding:28px;border-left:1px solid #29B6F6;border-right:1px solid #29B6F6;">
<h2 style="margin:0 0 12px;color:#fff;">${titel}</h2>
<p style="line-height:1.6;">${intro}</p>
<div style="line-height:1.6;">${bodyHtml}</div>
${actieUrl ? `<p style="text-align:center;margin:24px 0;"><a href="${actieUrl}" style="background:#29B6F6;color:#061224;font-weight:bold;padding:12px 28px;border-radius:24px;text-decoration:none;">${actieTekst || 'Bekijken'}</a></p>` : ''}
<p style="line-height:1.6;">${slot || 'Met vriendelijke groet,<br><b>Het CyberWolfert Team</b> 🐺'}</p>
</td></tr>
<tr><td style="padding:16px;text-align:center;color:#5B6B82;font-size:11px;">
Dit is een automatisch bericht van CyberWolfert. Reageer hier niet op.
</td></tr>
</table>
</td></tr>
</table>
</body></html>`;
}

async function sendMail(to, subject, html) {
  const t = getTransporter();
  if (!t) {
    console.warn('[mail] niet ingesteld (MAIL_HOST ontbreekt), mail naar', to, 'overgeslagen');
    return { sent: false, reason: 'mail_niet_ingesteld' };
  }
  try {
    await t.sendMail({ from: fromLine(), to, subject, html });
    return { sent: true };
  } catch (e) {
    console.error('[mail] verzenden mislukt:', e.message);
    return { sent: false, reason: e.message };
  }
}

const mails = {
  async accountAangemaakt(to, naam, verifyUrl, reportUrl) {
    return sendMail(
      to,
      'Welkom bij CyberWolfert 🐺 — bevestig je e-mailadres',
      brief({
        titel: `Welkom, ${naam}!`,
        intro: `Er is zojuist een CyberWolfert-account aangemaakt met dit e-mailadres. Bevestig hieronder dat dit adres van jou is om je account te activeren.`,
        bodyHtml: `<p>Je gebruikersnaam: <b>${naam}</b></p>`,
        actieUrl: verifyUrl,
        actieTekst: 'E-mailadres bevestigen',
        slot: `Was jij dit niet? Klik dan <a style="color:#29B6F6" href="${reportUrl}">hier</a> om het account direct te beveiligen, alle sessies uit te loggen en het apparaat te verbannen. Je kunt een verbannen apparaat later via e-mail weer deblokkeren.<br><br>Met vriendelijke groet,<br><b>Het CyberWolfert Team</b> 🐺`,
      })
    );
  },

  async apparaatVerbannen(to, naam, unbanUrl) {
    return sendMail(
      to,
      'CyberWolfert — apparaat verbannen',
      brief({
        titel: 'Apparaat verbannen',
        intro: `Hoi ${naam}, op jouw verzoek is een apparaat verbannen van je CyberWolfert-account. Dat apparaat kan niet meer inloggen en krijgt een melding te zien.`,
        bodyHtml: `<p>Wil je het apparaat toch weer toelaten? Gebruik onderstaande knop (alleen via deze e-mail mogelijk).</p>`,
        actieUrl: unbanUrl,
        actieTekst: 'Apparaat deblokkeren',
      })
    );
  },

  async apparaatGedeblokkeerd(to, naam) {
    return sendMail(
      to,
      'CyberWolfert — apparaat gedeblokkeerd',
      brief({
        titel: 'Apparaat gedeblokkeerd',
        intro: `Hoi ${naam}, het verbannen apparaat is weer toegelaten op je account. Was jij dit niet? Wijzig dan direct je wachtwoord en neem contact op.`,
        bodyHtml: '',
      })
    );
  },
};

module.exports = { sendMail, brief, baseUrl, mails };
