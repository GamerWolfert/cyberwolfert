// AeroTalk-gesprekken: WebRTC-signaling over WebSocket (audio/video/scherm).
// P2P tussen twee gebruikers; deze server doet alleen de koppeling (offer/answer/ICE)
// plus oproep-log (gemiste gesprekken). Zelfde poort als Express, pad "/ws".
const { WebSocketServer } = require('ws');
const crypto = require('crypto');
const { userIdFromToken } = require('./auth');
const db = require('./db');

const clients = new Map(); // uid -> Set<ws>
const calls = new Map(); // callId -> { caller, callee, kind, state, startedAt, timer }
const RING_MS = 45000;

function send(ws, obj) {
  if (ws.readyState === 1) {
    try {
      ws.send(JSON.stringify(obj));
    } catch (_) {}
  }
}
function sendTo(uid, obj) {
  const set = clients.get(uid);
  if (set) for (const ws of set) send(ws, obj);
}
function isOnline(uid) {
  return (clients.get(uid)?.size || 0) > 0;
}
async function nameOf(uid) {
  try {
    const r = await db.query('SELECT username, display_name FROM users WHERE id=$1', [uid]);
    const u = r.rows[0];
    if (!u) return 'Onbekend';
    return (u.display_name || u.username || '').trim() || 'Onbekend';
  } catch (_) {
    return 'Onbekend';
  }
}
function logCall(caller, callee, kind) {
  db.query(
    'INSERT INTO ws_calls (caller_id, callee_id, kind) VALUES ($1,$2,$3) RETURNING id',
    [caller, callee, kind]
  )
    .then((r) => r.rows[0]?.id)
    .catch(() => null);
}
function logDone(call, reason) {
  db.query(
    `UPDATE ws_calls SET ended_at=NOW(), end_reason=$2,
            duration_sec = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - started_at))::int)
      WHERE id=$1`,
    [call.logId, reason]
  ).catch(() => {});
}

function pickCall(callId, uid) {
  const c = calls.get(callId);
  if (!c || (c.caller !== uid && c.callee !== uid)) return null;
  return c;
}
function endCall(call, reason) {
  if (!call) return;
  clearTimeout(call.timer);
  calls.delete(call.id);
  sendTo(call.caller, { t: 'ended', call: call.id, reason });
  sendTo(call.callee, { t: 'ended', call: call.id, reason });
  logDone(call, reason);
}

function startCalls(server) {
  const wss = new WebSocketServer({ noServer: true });

  server.on('upgrade', (req, socket, head) => {
    let p = '';
    try {
      p = new URL(req.url, 'http://x').pathname;
    } catch (_) {}
    if (p !== '/ws') return; // geen andere upgrades → open laten voor andere servers
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
  });

  wss.on('connection', async (ws, req) => {
    let uid = null;
    try {
      const u = new URL(req.url, 'http://x');
      const token = u.searchParams.get('token') || '';
      uid = await userIdFromToken(token);
    } catch (_) {}
    if (!uid) {
      send(ws, { t: 'error', error: 'auth_required' });
      ws.close(4001, 'auth');
      return;
    }
    ws.uid = uid;
    if (!clients.has(uid)) clients.set(uid, new Set());
    clients.get(uid).add(ws);
    send(ws, { t: 'hello', me: uid, online: [...clients.keys()] });
    for (const other of clients.keys()) {
      if (other !== uid) sendTo(other, { t: 'online', users: [...clients.keys()] });
    }

    ws.on('message', async (raw) => {
      let m;
      try {
        m = JSON.parse(String(raw));
      } catch (_) {
        return;
      }
      try {
        await handle(ws, uid, m);
      } catch (e) {
        send(ws, { t: 'error', error: 'server', detail: String(e.message || e) });
      }
    });

    ws.on('close', () => {
      const set = clients.get(uid);
      if (set) {
        set.delete(ws);
        if (!set.size) clients.delete(uid);
      }
      // Actieve gesprekken van deze gebruiker beëindigen.
      for (const c of [...calls.values()]) {
        if (c.caller === uid || c.callee === uid) endCall(c, 'disconnect');
      }
      for (const other of clients.keys()) sendTo(other, { t: 'online', users: [...clients.keys()] });
    });
  });

  async function handle(ws, uid, m) {
    switch (m.t) {
      case 'invite': {
        const to = Number(m.to);
        const kind = ['audio', 'video', 'screen'].includes(m.kind) ? m.kind : 'video';
        if (!to || to === uid) return send(ws, { t: 'error', error: 'bad_invite' });
        if (!isOnline(to)) return send(ws, { t: 'error', error: 'offline', to });
        // Al in een gesprek? Beide richtingen controleren.
        for (const c of calls.values()) {
          if ((c.caller === uid || c.callee === uid) || (c.caller === to || c.callee === to)) {
            return send(ws, { t: 'error', error: 'busy' });
          }
        }
        const id = crypto.randomBytes(6).toString('hex');
        const log = await db
          .query(
            'INSERT INTO ws_calls (caller_id, callee_id, kind) VALUES ($1,$2,$3) RETURNING id',
            [uid, to, kind]
          )
          .then((r) => r.rows[0]?.id)
          .catch(() => null);
        const call = { id, caller: uid, callee: to, kind, state: 'ringing', logId: log };
        call.timer = setTimeout(() => endCall(call, 'missed'), RING_MS);
        calls.set(id, call);
        send(ws, { t: 'ringing', call: id, to, kind });
        sendTo(to, { t: 'incoming', call: id, from: uid, fromName: await nameOf(uid), kind });
        return;
      }
      case 'accept': {
        const c = pickCall(m.call, uid);
        if (!c || c.state !== 'ringing') return;
        clearTimeout(c.timer);
        c.state = 'active';
        c.startedAt = Date.now();
        sendTo(c.callee, { t: 'accepted', call: c.id, peer: c.caller });
        sendTo(c.caller, { t: 'accepted', call: c.id, peer: c.callee });
        return;
      }
      case 'reject': {
        const c = pickCall(m.call, uid);
        if (!c) return;
        endCall(c, 'rejected');
        return;
      }
      case 'hangup': {
        const c = pickCall(m.call, uid);
        if (!c) return;
        endCall(c, 'hangup');
        return;
      }
      case 'signal': {
        const c = pickCall(m.call, uid);
        if (!c) return;
        const peer = c.caller === uid ? c.callee : c.caller;
        sendTo(peer, { t: 'signal', call: c.id, from: uid, data: m.data });
        return;
      }
      case 'ping':
        return send(ws, { t: 'pong' });
      default:
        return send(ws, { t: 'error', error: 'unknown_type' });
    }
  }

  console.log('[calls] signaling klaar op /ws');
}

module.exports = { startCalls };
