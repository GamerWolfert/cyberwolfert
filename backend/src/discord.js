// Discord-logger: stuurt logregels naar de LOGS-SERVER kanalen.
// Alles fire-and-forget (logging mag de app nooit breken).
// Kanaal-IDs via config.env (zie .env.example).
const CHANNELS = {
  minipcLogins: process.env.DC_MINIPC_LOGINS,
  minipcSysteem: process.env.DC_MINIPC_SYSTEEM,
  minipcErrors: process.env.DC_MINIPC_ERRORS,
  cwZoektermen: process.env.DC_CW_ZOEKTERMEN,
  cwLogins: process.env.DC_CW_LOGINS,
  cwAi: process.env.DC_CW_AI,
  cwErrors: process.env.DC_CW_ERRORS,
  appsUpdates: process.env.DC_APPS_UPDATES,
  appsErrors: process.env.DC_APPS_ERRORS,
  wolfsyn: process.env.DC_CW_WOLFSYN,
  gamesLogs: process.env.DC_GAMES_LOGS,
  gamesCommandos: process.env.DC_GAMES_COMMANDOS,
  wolfbosPanel: process.env.DC_WOLFBOS_PANEL,
  wolfbosCommandos: process.env.DC_WOLFBOS_COMMANDOS,
  wolfbosLogins: process.env.DC_WOLFBOS_LOGINS,
  wolfbosErrors: process.env.DC_WOLFBOS_ERRORS,
  nlsmpPanel: process.env.DC_NLSMP_PANEL,
  nlsmpCommandos: process.env.DC_NLSMP_COMMANDOS,
  nlsmpLogins: process.env.DC_NLSMP_LOGINS,
  nlsmpErrors: process.env.DC_NLSMP_ERRORS,
};

async function send(channelId, text) {
  const token = process.env.DISCORD_BOT_TOKEN;
  if (!token || !channelId) return;
  try {
    const body = typeof text === 'string' ? { content: text.slice(0, 1900) } : text;
    await fetch(`https://discord.com/api/v10/channels/${channelId}/messages`, {
      method: 'POST',
      headers: { Authorization: `Bot ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  } catch (_) {}
}

function stamp() {
  return new Date().toISOString().replace('T', ' ').slice(0, 19);
}

async function naamOf(uid) {
  if (!uid) return 'gast';
  try {
    const db = require('./db');
    const r = await db.query('SELECT username FROM users WHERE id=$1', [uid]);
    return r.rows[0]?.username || `user#${uid}`;
  } catch {
    return `user#${uid}`;
  }
}

const log = {
  login: (wie, via) =>
    send(CHANNELS.cwLogins, `🔐 \`${stamp()}\` **${wie}** ingelogd via ${via}`),
  minipcLogin: (wie, via) =>
    send(CHANNELS.minipcLogins, `🔐 \`${stamp()}\` **${wie}** ingelogd op Mini-PC (${via})`),
  zoekterm: (wie, query) =>
    send(CHANNELS.cwZoektermen, `🔍 \`${stamp()}\` **${wie}**: ${query}`.slice(0, 1900)),
  ai: (wie, msg, engine) =>
    send(CHANNELS.cwAi, `🤖 \`${stamp()}\` **${wie}** (${engine}): ${msg}`.slice(0, 1900)),
  error: (waar, wat) =>
    send(CHANNELS.cwErrors, `⚠️ \`${stamp()}\` **${waar}**: ${String(wat).slice(0, 1500)}`),
  update: (versie, notes) =>
    send(CHANNELS.appsUpdates, `📱 \`${stamp()}\` **AeroSurf ${versie}** gepubliceerd: ${notes}`.slice(0, 1900)),
  wolfsyn: (msg) =>
    send(CHANNELS.wolfsyn, `🗑️ \`${stamp()}\` ${String(msg).slice(0, 1800)}`),
};

module.exports = { log, send, CHANNELS, naamOf };
