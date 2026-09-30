// Permissie-catalogus voor het admin-paneel (gegroepeerd, eerlijk en volledig).
// is_admin (gamerwolfert) mag ALLES, altijd.
const PERMS = {
  Gebruikers: [
    ['users.view', 'Gebruikers bekijken'],
    ['users.ban', 'Apparaten verbannen/deblokkeren'],
    ['users.delete', 'Accounts verwijderen'],
    ['users.verify', 'E-mail handmatig verifiëren'],
    ['users.resetpw', 'Wachtwoord opnieuw instellen'],
    ['users.make_admin', 'Admin-rechten geven/afnemen'],
  ],
  'Rollen & permissies': [
    ['roles.view', 'Rollen bekijken'],
    ['roles.create', 'Rollen aanmaken'],
    ['roles.edit', 'Rollen bewerken'],
    ['roles.delete', 'Rollen verwijderen'],
    ['roles.assign', 'Rollen toekennen aan gebruikers'],
    ['perms.grant', 'Losse permissies per gebruiker geven'],
  ],
  'Logs & inzicht': [
    ['logs.view', 'Logs bekijken'],
    ['logs.search', 'Zoektermen-log'],
    ['logs.ai', 'AI-chats-log'],
    ['logs.logins', 'Login/register-log'],
    ['logs.system', 'Systeemgebeurtenissen'],
  ],
  'Site & zoeken': [
    ['site.announce', 'Mededeling op startpagina'],
    ['site.stats', 'Statistieken bekijken'],
    ['site.links', 'Prioriteitslinks beheren'],
    ['site.maintenance', 'Onderhoudsmodus'],
  ],
  'AeroTalk & AI': [
    ['wolf.servers', 'AeroTalk-servers bekijken/verwijderen'],
    ['ai.memory', 'AI-geheugen van gebruikers wissen'],
    ['ai.engine', 'AI-engine instellen'],
    ['agent.run', 'AI-agent op de Mini-PC laten uitvoeren'],
    ['mail.test', 'Testmail versturen'],
  ],
  'E-mail': [
    ['mail.manage', 'Mailboxen aanmaken, toegang geven, eigendom overdragen'],
  ],
};

const ALL_PERMS = Object.values(PERMS).flat();

async function isAdmin(db, userId) {
  try {
    const r = await db.query('SELECT is_admin FROM users WHERE id=$1', [userId]);
    return !!r.rows[0]?.is_admin;
  } catch {
    return false;
  }
}

// Effectieve permissies: admin = alles; anders rollen + per-user overrides.
async function effectivePerms(db, userId) {
  if (await isAdmin(db, userId)) {
    return Object.fromEntries(ALL_PERMS.map(([k]) => [k, true]));
  }
  const out = {};
  try {
    const r = await db.query(
      `SELECT ro.permissions FROM site_user_roles ur
       JOIN site_roles ro ON ro.name=ur.role_name WHERE ur.user_id=$1`,
      [userId]
    );
    for (const row of r.rows) {
      const p = row.permissions || {};
      for (const [k, v] of Object.entries(p)) if (v) out[k] = true;
    }
    const o = await db.query('SELECT perm, allow FROM site_user_perms WHERE user_id=$1', [userId]);
    for (const row of o.rows) {
      if (row.allow) out[row.perm] = true;
      else delete out[row.perm];
    }
  } catch (_) {}
  return out;
}

function requirePerm(perm) {
  return async (req, res, next) => {
    const { authRequired } = require('./auth');
    return authRequired(req, res, async () => {
      const db = require('./db');
      const perms = await effectivePerms(db, req.userId);
      if (!perms[perm]) return res.status(403).json({ error: 'geen toestemming' });
      req.perms = perms;
      next();
    });
  };
}

module.exports = { PERMS, ALL_PERMS, isAdmin, effectivePerms, requirePerm };
