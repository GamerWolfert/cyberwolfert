// Eigen SMTP-server (inkomende mail) + lokale bezorging in mailboxen.
// - Luistert op MAIL_SMTP_PORTS (standaard '2525,25'; poort 25 heeft root/CAP_NET_BIND_SERVICE nodig).
// - GEEN open relay: alleen adressen op onze eigen actieve domeinen worden geaccepteerd.
// - Zonder externe dependencies: eigen SMTP-state-machine + MIME/header-parsing.
// - Webhook-relay (POST /api/mail/webhook) komt hier ook op dezelfde bezorger uit.
const net = require('net');
const db = require('./db');
const { log } = require('./discord');

const DEFAULT_PORTS = '2525,25';
const MAX_LINE = 4096;
const MAX_DATA = 5 * 1024 * 1024;
const HOSTNAME = process.env.MAIL_SMTP_HOSTNAME || 'cyberwolfert';

const listening = [];

// ---------------- headers / MIME ----------------

function decodeWords(v) {
  let s = String(v || '').replace(/\?=\s+=\?/g, '?==?');
  return s.replace(/=\?([^?]+)\?([BbQq])\?([^?]*)\?=/g, (m, _cs, enc, data) => {
    try {
      if (String(enc).toUpperCase() === 'B') {
        return Buffer.from(data, 'base64').toString('utf8');
      }
      const q = String(data)
        .replace(/_/g, ' ')
        .replace(/=([0-9A-Fa-f]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
      return Buffer.from(q, 'latin1').toString('utf8');
    } catch (_) {
      return m;
    }
  });
}

function decodeQuotedPrintable(s) {
  const t = String(s || '').replace(/=\r?\n/g, '');
  const bytes = t.replace(/=([0-9A-Fa-f]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
  return Buffer.from(bytes, 'latin1').toString('utf8');
}

function decodeBody(body, cte) {
  const c = String(cte || '').toLowerCase();
  try {
    if (c.includes('base64')) return Buffer.from(String(body).replace(/\s/g, ''), 'base64').toString('utf8');
    if (c.includes('quoted-printable')) return decodeQuotedPrintable(body);
  } catch (_) {}
  return String(body || '');
}

function addrOf(v) {
  const s = decodeWords(v);
  const ang = /<([^>]+)>/.exec(s);
  if (ang) return ang[1].trim();
  const em = /[^\s<>,;"]+@[^\s<>,;"]+\.[^\s<>,;"]+/.exec(s);
  return em ? em[0].trim() : s.trim().slice(0, 254);
}

function nameOf(v) {
  const s = decodeWords(v);
  const ang = /<([^>]+)>/.exec(s);
  if (ang && s.replace(ang[0], '').trim()) return s.replace(ang[0], '').replace(/"/g, '').trim();
  return '';
}

function stripHtml(html) {
  let t = String(html || '');
  t = t.replace(/<(script|style)[\s\S]*?<\/\1>/gi, ' ');
  t = t.replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|tr|li|h[1-6])>/gi, '\n');
  t = t.replace(/<[^>]+>/g, '');
  t = t
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&#(\d+);/g, (_, d) => String.fromCharCode(Number(d)));
  return t.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}

function parseHeaders(block) {
  const out = {};
  let cur = null;
  for (const line of String(block || '').split('\n')) {
    if (/^[ \t]/.test(line) && cur) out[cur] += ' ' + line.trim();
    else {
      const i = line.indexOf(':');
      if (i > 0) {
        cur = line.slice(0, i).trim().toLowerCase();
        out[cur] = line.slice(i + 1).trim();
      }
    }
  }
  return out;
}

// Verificatiecode-patroon: "je code is 123456", "code: 8421", "OTP 993021" ...
function extractCode(text) {
  const t = String(text || '');
  const pats = [
    /\b(?:code|otp|pin|verificatiecode|bevestigingscode|validatiecode|wachtwoordcode|activation code|one[- ]?time code|tijdelijke code)\b[^0-9]{0,30}([0-9]{4,8})\b/i,
    /\b([0-9]{4,8})\b\s*(?:is (?:je|uw|jouw|your|de) (?:code|otp|pin)|is your (?:code|otp))/i,
    /\b(?:is dit|dit is) (?:je|uw|jouw|your) (?:code|otp)\b[^0-9]{0,10}([0-9]{4,8})/i,
  ];
  for (const p of pats) {
    const m = p.exec(t);
    if (m && m[1]) return m[1];
  }
  const loose = /\b([0-9]{6,8})\b/.exec(t.slice(0, 800));
  return loose ? loose[1] : null;
}

function parseMessage(raw) {
  const norm = String(raw || '').replace(/\r\n/g, '\n');
  const idx = norm.search(/\n\n/);
  const headBlock = idx >= 0 ? norm.slice(0, idx) : norm;
  const bodyRaw = idx >= 0 ? norm.slice(idx + 2) : '';
  const h = parseHeaders(headBlock);
  const ctype = h['content-type'] || '';
  const cte = h['content-transfer-encoding'] || '';

  let text = '';
  let html = '';
  const bnd = /boundary="?([^";\s]+)"?/i.exec(ctype);

  if (/multipart\//i.test(ctype) && bnd) {
    const parts = bodyRaw.split('--' + bnd[1]);
    for (const p of parts) {
      if (p.trimStart().startsWith('--')) continue;
      const pi = p.search(/\n\n/);
      if (pi < 0) continue;
      const ph = p.slice(0, pi).toLowerCase();
      const pb = p.slice(pi + 2).replace(/\n+$/, '');
      const pct = (/content-type:\s*([^\n;]+)/i.exec(ph) || [])[1] || '';
      const pcte = (/content-transfer-encoding:\s*([^\n;]+)/i.exec(ph) || [])[1] || '';
      const dec = decodeBody(pb, pcte);
      if (!text && /text\/plain/i.test(pct)) text = dec;
      else if (!html && /text\/html/i.test(pct)) html = dec;
      if (text && html) break;
    }
  } else {
    const dec = decodeBody(bodyRaw, cte);
    if (/text\/html/i.test(ctype)) html = dec;
    else text = dec;
  }
  if (!text && html) text = stripHtml(html);

  const mid = h['message-id'] || '';
  return {
    from: addrOf(h.from || ''),
    fromName: nameOf(h.from || ''),
    to: addrOf(h.to || ''),
    subject: decodeWords(h.subject || '').slice(0, 900),
    date: h.date || '',
    text: String(text || '').slice(0, 200000),
    html: String(html || '').slice(0, 400000),
    messageId: mid.replace(/[<>]/g, '').trim(),
    code: extractCode(text || stripHtml(html)),
  };
}

// ---------------- bezorging ----------------

async function findMailbox(address) {
  const a = String(address || '').trim().replace(/^<|>$/g, '');
  const at = a.lastIndexOf('@');
  if (at <= 0) return null;
  const local = a.slice(0, at).toLowerCase();
  const domain = a.slice(at + 1).toLowerCase();
  const r = await db.query(
    `SELECT mb.id, mb.localpart, d.domain
       FROM mail_mailboxes mb JOIN mail_domains d ON d.id = mb.domain_id
      WHERE d.active AND LOWER(d.domain) = $1 AND LOWER(mb.localpart) = $2`,
    [domain, local]
  );
  if (!r.rows.length) return null;
  return { id: r.rows[0].id, address: `${r.rows[0].localpart}@${r.rows[0].domain}` };
}

async function isLocalAddress(address) {
  return !!(await findMailbox(address));
}

// Zet een bericht in de mailbox (returnt bericht-id of null bij dubbel/dood adres).
async function deliverLocal(toAddress, msg) {
  const box = await findMailbox(toAddress);
  if (!box) return null;
  const ext = msg.externalId || null;
  try {
    const r = await db.query(
      `INSERT INTO mail_messages
         (mailbox_id, dir, from_addr, to_addr, subject, body_text, body_html, code, external_id)
       VALUES ($1,'in',$2,$3,$4,$5,$6,$7,$8)
       ON CONFLICT (external_id) WHERE external_id IS NOT NULL DO NOTHING
       RETURNING id`,
      [
        box.id,
        String(msg.from || '').slice(0, 254),
        box.address,
        String(msg.subject || '').slice(0, 900),
        String(msg.text || ''),
        String(msg.html || ''),
        msg.code || null,
        ext,
      ]
    );
    if (r.rows.length) {
      const id = r.rows[0].id;
      console.log(`[smtp] inbound -> ${box.address} (#${id})`);
      log.wolfsyn(
        `\`[${new Date().toISOString().replace('T', ' ').slice(0, 19)}]\` **mail** \`${box.address}\` <- \`${(msg.from || '?').slice(0, 80)}\`: ${(msg.subject || '(geen onderwerp)').slice(0, 120)}${msg.code ? ` (code \`${msg.code}\`)` : ''}`
      );
      return id;
    }
    return null;
  } catch (e) {
    console.error('[smtp] bezorgen mislukt:', e.message);
    return null;
  }
}

// ---------------- SMTP-server ----------------

function write(sock, line) {
  if (!sock.destroyed) sock.write(line + '\r\n');
}

function extractAddress(arg) {
  const ang = /<([^>]*)>/.exec(arg || '');
  if (ang) return ang[1].trim();
  return String(arg || '').trim().split(/\s+/)[0] || '';
}

async function handleCmd(line, st, sock) {
  const m = /^([A-Za-z]+)\s?(.*)$/.exec(line);
  const verb = (m ? m[1] : line).toUpperCase();
  const rest = m ? m[2] : '';

  switch (verb) {
    case 'EHLO':
      write(sock, `250-${HOSTNAME} Hello`);
      write(sock, '250-8BITMIME');
      write(sock, '250-PIPELINING');
      write(sock, '250 HELP');
      return;
    case 'HELO':
      write(sock, `250 ${HOSTNAME}`);
      return;
    case 'MAIL': {
      if (/^FROM:/i.test(rest)) {
        st.from = extractAddress(rest.replace(/^FROM:/i, ''));
        st.tos = [];
        write(sock, '250 2.1.0 Ok');
      } else write(sock, '501 5.5.4 Syntax: MAIL FROM:<address>');
      return;
    }
    case 'RCPT': {
      if (!/^TO:/i.test(rest)) return write(sock, '501 5.5.4 Syntax: RCPT TO:<address>');
      const addr = extractAddress(rest.replace(/^TO:/i, ''));
      try {
        const box = await findMailbox(addr);
        if (!box) {
          write(sock, '550 5.1.1 Geen mailbox op dit adres (geen open relay)');
          return;
        }
        st.tos.push(addr);
        write(sock, '250 2.1.5 Ok');
      } catch (e) {
        console.error('[smtp] rcpt fout:', e.message);
        write(sock, '451 4.3.0 Tijdelijke fout');
      }
      return;
    }
    case 'DATA':
      if (!st.tos.length) return write(sock, '503 5.5.1 Eerst MAIL FROM + RCPT TO');
      st.mode = 'data';
      st.data = '';
      write(sock, '354 End data with <CR><LF>.<CR><LF>');
      return;
    case 'RSET':
      st.from = null;
      st.tos = [];
      st.data = '';
      write(sock, '250 2.0.0 Ok');
      return;
    case 'NOOP':
      write(sock, '250 2.0.0 Ok');
      return;
    case 'VRFY':
      write(sock, '252 Kan adressen niet verifiëren');
      return;
    case 'HELP':
      write(sock, '214 AeroSurf mailserver');
      return;
    case 'QUIT':
      write(sock, '221 2.0.0 Bye');
      sock.end();
      st.tos = [];
      return;
    default:
      write(sock, '500 5.5.2 Commando niet herkend');
  }
}

async function finishData(st, sock) {
  const raw = st.data.replace(/(^|\r\n)\.\./g, '$1');
  const recipients = st.tos.slice();
  st.mode = 'cmd';
  st.data = '';
  st.tos = [];
  if (!recipients.length) return write(sock, '503 5.5.1 Geen ontvangers');
  if (!raw.trim()) return write(sock, '554 5.6.0 Leeg bericht');

  let parsed;
  try {
    parsed = parseMessage(raw);
  } catch (e) {
    console.error('[smtp] parse fout:', e.message);
    return write(sock, '451 4.3.0 Kon bericht niet verwerken');
  }
  if (!parsed.from) parsed.from = st.from || '';

  for (const rcpt of recipients) {
    await deliverLocal(rcpt, {
      from: parsed.from,
      subject: parsed.subject,
      text: parsed.text,
      html: parsed.html,
      code: parsed.code,
      externalId: parsed.messageId ? `smtp:${rcpt}:${parsed.messageId}` : null,
    });
  }
  write(sock, '250 2.0.0 Ok: bericht geaccepteerd');
}

function handleConn(sock) {
  sock.setEncoding('utf8');
  sock.setTimeout(120000, () => sock.destroy());
  const st = { buf: '', mode: 'cmd', from: null, tos: [], data: '', chain: Promise.resolve() };
  write(sock, `220 ${HOSTNAME} ESMTP AeroSurf klaar`);

  sock.on('data', (chunk) => {
    st.buf += chunk;
    st.chain = st.chain
      .then(async () => {
        let guard = 0;
        while (guard++ < 5000) {
          if (st.mode === 'data') {
            const end = st.buf.indexOf('\r\n.\r\n');
            if (end < 0) {
              if (st.buf.length > MAX_DATA) {
                st.mode = 'cmd';
                st.buf = '';
                st.data = '';
                write(sock, '552 5.3.4 Bericht te groot');
              }
              return;
            }
            st.data += st.buf.slice(0, end);
            st.buf = st.buf.slice(end + 5);
            await finishData(st, sock);
            continue;
          }
          const nl = st.buf.indexOf('\r\n');
          if (nl < 0) return;
          let line = st.buf.slice(0, nl);
          st.buf = st.buf.slice(nl + 2);
          if (line.length > MAX_LINE) line = line.slice(0, MAX_LINE);
          await handleCmd(line, st, sock);
          if (sock.destroyed) return;
        }
      })
      .catch((e) => console.error('[smtp] sessiefout:', e.message));
  });
  sock.on('error', () => {});
  sock.on('close', () => {});
}

function startSmtp() {
  const ports = String(process.env.MAIL_SMTP_PORTS || DEFAULT_PORTS)
    .split(',')
    .map((s) => Number(s.trim()))
    .filter((n) => Number.isFinite(n) && n > 0);

  for (const port of ports) {
    let srv;
    try {
      srv = net.createServer(handleConn);
    } catch (e) {
      console.warn(`[smtp] poort ${port} kon niet gemaakt worden: ${e.message}`);
      continue;
    }
    srv.on('error', (e) => {
      console.warn(`[smtp] poort ${port}: ${e.message}${e.code === 'EACCES' ? ' (poort 25 vereist root/CAP_NET_BIND_SERVICE)' : ''}`);
    });
    srv.on('listening', () => {
      listening.push(port);
      console.log(`[smtp] inkomende mail op poort ${port}`);
    });
    try {
      srv.listen(port, '0.0.0.0');
    } catch (e) {
      console.warn(`[smtp] poort ${port} starten mislukt: ${e.message}`);
    }
  }
}

function smtpStatus() {
  return {
    ports: listening,
    hostname: HOSTNAME,
    portsWanted: String(process.env.MAIL_SMTP_PORTS || DEFAULT_PORTS),
  };
}

module.exports = { startSmtp, smtpStatus, deliverLocal, findMailbox, isLocalAddress, parseMessage, extractCode };
