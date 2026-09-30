// AeroSurf Mail: officiele e-mails in huisstijl (logo, banner, formele brief).
// Werkt lokaal op de Mini-PC en bezorgt via een SMTP-relay naar het open
// netwerk (Gmail/Brevo-gratis). Een volledig eigen SMTP-server vanaf een
// thuisnetwerk levert vrijwel niets af (geen PTR/reputatie, poort 25 dicht),
// daarom: eigen afzender-naam + relay. Config via config.env (MAIL_*).
const nodemailer = require('nodemailer');
const { deliverLocal, extractCode } = require('./smtp');

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
  const name = process.env.MAIL_FROM_NAME || 'AeroSurf Team';
  const addr = process.env.MAIL_FROM || 'no-reply@cyberwolfert.local';
  return `"${name}" <${addr}>`;
}

function baseUrl() {
  return (process.env.PUBLIC_URL || `http://192.168.1.42:${process.env.PORT || 43711}`).replace(/\/$/, '');
}

// Officiele brief-layout: logo, banner, inhoud, groet, footer.
// Logo is een echte afbeelding (serverd /assets/logo.png) i.p.v. een emoji.
function brief({ titel, intro, bodyHtml, actieUrl, actieTekst, slot, logo }) {
  const img = logo || `${baseUrl()}/assets/logo.png`;
  return `<!DOCTYPE html><html lang="nl"><head><meta charset="utf-8"></head>
<body style="margin:0;background:#F1F4F8;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#F1F4F8;padding:24px 0;">
<tr><td align="center">
<table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;background:#FFFFFF;border:1px solid #E1E6ED;border-radius:10px;overflow:hidden;">
<tr><td style="background:#0B1220;padding:24px 28px;border-bottom:3px solid #3CFF5C;">
<table cellpadding="0" cellspacing="0"><tr>
<td style="vertical-align:middle;padding-right:14px;">
<img src="${img}" width="44" height="44" alt="AeroSurf" style="display:block;border-radius:10px;">
</td>
<td style="vertical-align:middle;">
<div style="color:#FFFFFF;font-size:22px;font-weight:800;letter-spacing:1.5px;">AERO<span style="color:#3CFF5C;">SURF</span></div>
<div style="color:#8FA0B8;font-size:11px;letter-spacing:.6px;text-transform:uppercase;">Officieel bericht</div>
</td>
</tr></table>
</td></tr>
<tr><td style="padding:28px;color:#1B2432;">
<h2 style="margin:0 0 12px;color:#0B1220;font-size:20px;">${titel}</h2>
<p style="line-height:1.65;color:#3B4657;">${intro}</p>
<div style="line-height:1.65;color:#3B4657;">${bodyHtml}</div>
${actieUrl ? `<p style="text-align:center;margin:26px 0;"><a href="${actieUrl}" style="background:#0B1220;color:#FFFFFF;font-weight:bold;padding:13px 30px;border-radius:6px;text-decoration:none;display:inline-block;">${actieTekst || 'Bekijken'}</a></p>` : ''}
<p style="line-height:1.65;color:#3B4657;">${slot || 'Met vriendelijke groet,<br><b>AeroSurf</b>'}</p>
</td></tr>
<tr><td style="background:#F7F9FC;padding:16px 28px;color:#7C8798;font-size:11px;border-top:1px solid #E1E6ED;">
Dit is een automatisch bericht van AeroSurf. Reageer hier niet op.<br>
AeroSurf &middot; ${baseUrl()}
</td></tr>
</table>
</td></tr>
</table>
</body></html>`;
}

// Verstuurt een mail. Eigen adressen (naam@onze-domeinen) worden direct in de
// mailbox op de Mini-PC bezorgd — dus ook verificatiemails van de site zelf
// komen in de webmail terecht zodra je je adres als mailbox hebt aangemaakt.
async function sendMail(to, subject, html, text) {
  const plain = text || String(html || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
  try {
    const local = await deliverLocal(to, {
      from: process.env.MAIL_FROM || 'no-reply@cyberwolfert.nl',
      subject,
      html,
      text: plain,
      code: extractCode(plain),
      externalId: null,
    });
    if (local) return { sent: true, local: true };
  } catch (e) {
    console.warn('[mail] lokale bezorging mislukt:', e.message);
  }
  const t = getTransporter();
  if (!t) {
    console.warn('[mail] niet ingesteld (MAIL_HOST ontbreekt), mail naar', to, 'overgeslagen');
    return { sent: false, reason: 'relay_niet_ingesteld' };
  }
  try {
    await t.sendMail({ from: fromLine(), to, subject, html, text: plain });
    console.log(`[mail] verzonden naar ${to} — ${subject}`);
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
      'Welkom bij AeroSurf — bevestig je e-mailadres',
      brief({
        titel: `Welkom, ${naam}!`,
        intro: `Er is zojuist een AeroSurf-account aangemaakt met dit e-mailadres. Bevestig hieronder dat dit adres van jou is om je account te activeren.`,
        bodyHtml: `<p>Je gebruikersnaam: <b>${naam}</b></p>`,
        actieUrl: verifyUrl,
        actieTekst: 'E-mailadres bevestigen',
        slot: `Was jij dit niet? Klik dan <a style="color:#0B1220;font-weight:bold" href="${reportUrl}">hier</a> om het account direct te beveiligen, alle sessies uit te loggen en het apparaat te verbannen. Je kunt een verbannen apparaat later via e-mail weer deblokkeren.<br><br>Met vriendelijke groet,<br><b>AeroSurf</b>`,
      })
    );
  },

  async apparaatVerbannen(to, naam, unbanUrl) {
    return sendMail(
      to,
      'AeroSurf — apparaat verbannen',
      brief({
        titel: 'Apparaat verbannen',
        intro: `Hoi ${naam}, op jouw verzoek is een apparaat verbannen van je AeroSurf-account. Dat apparaat kan niet meer inloggen en krijgt een melding te zien.`,
        bodyHtml: `<p>Wil je het apparaat toch weer toelaten? Gebruik onderstaande knop (alleen via deze e-mail mogelijk).</p>`,
        actieUrl: unbanUrl,
        actieTekst: 'Apparaat deblokkeren',
      })
    );
  },

  async apparaatGedeblokkeerd(to, naam) {
    return sendMail(
      to,
      'AeroSurf — apparaat gedeblokkeerd',
      brief({
        titel: 'Apparaat gedeblokkeerd',
        intro: `Hoi ${naam}, het verbannen apparaat is weer toegelaten op je account. Was jij dit niet? Wijzig dan direct je wachtwoord en neem contact op.`,
        bodyHtml: '',
      })
    );
  },

  // Officiele melding zodra de publieke website-URL wijzigt (nieuwe tunnel).
  async urlGewijzigd(to, oudeUrl, nieuweUrl) {
    return sendMail(
      to,
      `AeroSurf — nieuwe publieke website-URL (${new Date().toLocaleDateString('nl-NL')})`,
      brief({
        titel: 'De website-URL is gewijzigd',
        intro:
          'Dit is een officiële melding van AeroSurf. De publieke URL waarop de website en backend bereikbaar zijn, is zojuist veranderd (nieuwe quick-tunnel).',
        bodyHtml: `<p style="margin:0 0 6px;"><b>Oude URL</b></p>
<p style="margin:0 0 14px;font-family:monospace;font-size:13px;color:#5A6779;">${oudeUrl || '(nog geen bekende URL)'}</p>
<p style="margin:0 0 6px;"><b>Nieuwe URL</b></p>
<p style="margin:0 0 14px;font-family:monospace;font-size:13px;"><a style="color:#0B1220" href="${nieuweUrl}">${nieuweUrl}</a></p>
<p style="margin:0;font-size:13px;color:#5A6779;">Tijd: ${new Date().toLocaleString('nl-NL')} (lokale tijd)</p>`,
        actieUrl: nieuweUrl,
        actieTekst: 'Open de nieuwe URL',
        slot: 'Bewaar dit adres of gebruik de link hierboven. Deze melding wordt automatisch verstuurd bij elke URL-wijziging.<br><br>Met vriendelijke groet,<br><b>AeroSurf</b>',
      })
    );
  },
};

module.exports = { sendMail, brief, baseUrl, mails };
