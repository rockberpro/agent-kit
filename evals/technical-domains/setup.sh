#!/usr/bin/env bash
# Fixture: a websocket chat server. Its domains (transport, presence, delivery) are
# technical, with invariants and no business rules. Runs in the case workspace.
set -euo pipefail

mkdir -p src/transport src/presence src/delivery .agents/memory .agents/rules

cat > README.md <<'EOF'
# Chat server

Realtime chat over WebSockets. Node 20, no database: rooms live in memory.
EOF

cat > AGENTS.md <<'EOF'
# Chat server — Agent Guide

## Memory Catalog

Persistent instructions live in `./.agents/memory/`. Index:
[.agents/memory/MEMORY.md](.agents/memory/MEMORY.md).

Notes and rules under `.agents/` are written in English (`en`).
EOF

cat > package.json <<'EOF'
{ "name": "chat-server", "type": "module", "dependencies": { "ws": "^8.18.0" } }
EOF

cat > src/transport/server.js <<'EOF'
import { WebSocketServer } from 'ws';
import { join, leave } from '../presence/tracker.js';
import { publish, ack } from '../delivery/queue.js';

// Clients must answer a ping within 30s or the socket is closed with 4000.
const HEARTBEAT_MS = 30_000;

export function start(port) {
  const wss = new WebSocketServer({ port });
  wss.on('connection', (ws, req) => {
    const user = new URL(req.url, 'ws://x').searchParams.get('user');
    ws.alive = true;
    ws.on('pong', () => { ws.alive = true; });
    join(user, ws);
    ws.on('message', (raw) => {
      const msg = JSON.parse(raw);
      if (msg.type === 'ack') ack(user, msg.id);
      else publish(msg.room, { id: msg.id, from: user, text: msg.text });
    });
    ws.on('close', () => leave(user));
  });
  setInterval(() => wss.clients.forEach((ws) => {
    if (!ws.alive) return ws.close(4000, 'heartbeat timeout');
    ws.alive = false; ws.ping();
  }), HEARTBEAT_MS);
}
EOF

cat > src/presence/tracker.js <<'EOF'
// A user is online while at least one socket is open; several tabs share one presence.
const sockets = new Map();

export function join(user, ws) {
  if (!sockets.has(user)) sockets.set(user, new Set());
  sockets.get(user).add(ws);
}

export function leave(user) {
  // Offline only after a 5s grace period, so a reconnect does not flap presence.
  setTimeout(() => { if (!sockets.get(user)?.size) sockets.delete(user); }, 5_000);
}

export const socketsOf = (user) => sockets.get(user) ?? new Set();
EOF

cat > src/delivery/queue.js <<'EOF'
import { socketsOf } from '../presence/tracker.js';

// Per-room ordering: every message gets the room's next sequence number, and clients
// render by seq, never by arrival. Delivery is at-least-once: a message is resent until
// acked, so clients must dedupe by message id.
const seq = new Map();
const pending = new Map();

export function publish(room, msg) {
  const next = (seq.get(room) ?? 0) + 1;
  seq.set(room, next);
  const out = { ...msg, room, seq: next };
  for (const user of membersOf(room)) {
    pending.set(`${user}:${msg.id}`, out);
    socketsOf(user).forEach((ws) => ws.send(JSON.stringify(out)));
  }
}

export function ack(user, id) { pending.delete(`${user}:${id}`); }

function membersOf(room) { return rooms.get(room) ?? []; }
const rooms = new Map();
EOF

git init -q
git add -A
git -c user.name=eval -c user.email=eval@example.com commit -qm "feat: chat server"
