// Integration test: two clients join, see each other, and one kills the other.
// YUKKURI STRIKE - created by ゆっくりP
'use strict';
process.env.PORT = '0';
const assert = require('assert');
const WebSocket = require('ws');
const { server, wss } = require('./index.js');

function client(port, name) {
  return new Promise((resolve) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    const c = { ws, msgs: [], welcome: null };
    ws.on('open', () => ws.send(JSON.stringify({ t: 'hello', name, ver: 1 })));
    ws.on('message', (d) => {
      const m = JSON.parse(d.toString());
      c.msgs.push(m);
      if (m.t === 'welcome') { c.welcome = m; resolve(c); }
    });
  });
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

server.on('listening', async () => {
  const port = server.address().port;
  const a = await client(port, 'Alice');
  const b = await client(port, 'Bob');
  assert.notStrictEqual(a.welcome.team, b.welcome.team, 'teams are balanced');
  assert.strictEqual(a.welcome.creator, 'ゆっくりP');
  a.ws.send(JSON.stringify({ t: 'st', p: [1, 2, 3], r: [0.5, 0], c: false, w: 'ar', v: -1, a: true }));
  await wait(150);
  const snap = b.msgs.filter((m) => m.t === 'snap').pop();
  assert.ok(snap && snap.pl.length === 2, 'snapshot contains both players');
  assert.deepStrictEqual(snap.pl.find((p) => p.id === a.welcome.id).p, [1, 2, 3]);
  for (let i = 0; i < 4; i++) a.ws.send(JSON.stringify({ t: 'hit', v: b.welcome.id, d: 30, h: false, w: 'ar' }));
  await wait(150);
  const kill = b.msgs.find((m) => m.t === 'kill');
  assert.ok(kill && kill.v === b.welcome.id && kill.by === a.welcome.id, 'kill broadcast');
  const capped = { t: 'hit', v: a.welcome.id, d: 99999, w: 'ar' };
  b.ws.send(JSON.stringify({ t: 'spawn' }));
  await wait(50);
  b.ws.send(JSON.stringify(capped));
  await wait(150);
  const dmg = a.msgs.filter((m) => m.t === 'dmg' && m.v === a.welcome.id).pop();
  assert.ok(dmg && dmg.hp === 20, 'damage is clamped server-side');
  a.ws.send(JSON.stringify({ t: 'ping', c: 42 }));
  await wait(100);
  assert.ok(a.msgs.find((m) => m.t === 'pong' && m.c === 42), 'pong');
  console.log('server test OK');
  a.ws.close(); b.ws.close(); wss.close(); server.close();
  process.exit(0);
});
