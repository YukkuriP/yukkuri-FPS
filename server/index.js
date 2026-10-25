// YUKKURI STRIKE - multiplayer relay/authority server for Render.com
// Created by ゆっくりP
//
// Design: clients simulate their own movement and detect their own hits;
// the server owns HP, kills, tickets and vehicle health, relays world events
// (shots, explosions, grenades) and broadcasts compact 20 Hz snapshots.
'use strict';
const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = parseInt(process.env.PORT || '10000', 10);
const ROOM_SIZE = parseInt(process.env.ROOM_SIZE || '16', 10);
const TICK_HZ = 20;
const START_TICKETS = 250;
const PROTOCOL_VERSION = 1;
const MAP_SEED = 20260125;
const VEHICLE_HP = { jeep: 420, tank: 1400 };
const MAX_HIT = { ar: 80, smg: 60, dmr: 260, rpg: 200, shell: 240, mg: 60, grenade: 160, vehicle: 200, crush: 0, fall: 999 };
const CREATOR = 'ゆっくりP';

let nextId = 1;
const rooms = [];

function r2(v) { return Math.round(v * 100) / 100; }

class Room {
  constructor(id) {
    this.id = id;
    this.players = new Map();
    this.reset();
  }
  reset() {
    this.tickets = [START_TICKETS, START_TICKETS];
    this.vehicles = new Map();
    this.ended = false;
    for (const p of this.players.values()) { p.hp = 100; p.alive = true; p.k = 0; p.d = 0; }
  }
  teamCounts() {
    const c = [0, 0];
    for (const p of this.players.values()) c[p.team]++;
    return c;
  }
  add(p) {
    const c = this.teamCounts();
    p.team = c[0] <= c[1] ? 0 : 1;
    p.room = this;
    this.players.set(p.id, p);
  }
  remove(p) {
    this.players.delete(p.id);
    this.broadcast({ t: 'leave', id: p.id });
  }
  broadcast(msg, except) {
    const raw = JSON.stringify(msg);
    for (const p of this.players.values()) {
      if (p !== except && p.ws.readyState === 1) p.ws.send(raw);
    }
  }
  vehicle(id, kind) {
    if (!this.vehicles.has(id)) this.vehicles.set(id, { hp: VEHICLE_HP[kind] || 500, dead: false });
    return this.vehicles.get(id);
  }
  snapshot() {
    const pl = [];
    const vs = [];
    for (const p of this.players.values()) {
      pl.push({ id: p.id, n: p.name, tm: p.team, p: p.pos, r: p.rot, c: p.crouch, w: p.weapon, v: p.veh, a: p.alive, hp: Math.max(0, Math.round(p.hp)), k: p.k, d: p.d });
      if (p.vs && p.veh >= 0) vs.push(p.vs);
    }
    return { t: 'snap', pl, vs, tk: this.tickets };
  }
  damage(attacker, victim, dmg, head, weapon) {
    if (this.ended || !victim.alive) return;
    victim.hp -= dmg;
    this.broadcast({ t: 'dmg', v: victim.id, by: attacker ? attacker.id : -1, hp: Math.max(0, Math.round(victim.hp)), d: Math.round(dmg) });
    if (victim.hp <= 0) {
      victim.alive = false;
      victim.d++;
      victim.veh = -1;
      victim.vs = null;
      if (attacker && attacker !== victim) attacker.k++;
      this.tickets[victim.team] = Math.max(0, this.tickets[victim.team] - 1);
      this.broadcast({ t: 'kill', v: victim.id, by: attacker ? attacker.id : -1, w: weapon, h: !!head });
      if (this.tickets[victim.team] <= 0) this.end(1 - victim.team);
    }
  }
  end(winner) {
    this.ended = true;
    this.broadcast({ t: 'end', winner });
    setTimeout(() => this.reset(), 12000);
  }
}

function findRoom() {
  for (const r of rooms) if (r.players.size < ROOM_SIZE && !r.ended) return r;
  const r = new Room(rooms.length + 1);
  rooms.push(r);
  return r;
}

function handle(p, msg) {
  const room = p.room;
  switch (msg.t) {
    case 'ping':
      p.ws.send(JSON.stringify({ t: 'pong', c: msg.c }));
      return;
    case 'st':
      if (Array.isArray(msg.p) && msg.p.length === 3) p.pos = msg.p.map((x) => r2(+x || 0));
      if (Array.isArray(msg.r) && msg.r.length === 2) p.rot = msg.r.map((x) => +x || 0);
      p.crouch = !!msg.c;
      p.weapon = typeof msg.w === 'string' ? msg.w.slice(0, 8) : 'ar';
      p.veh = Number.isInteger(msg.v) ? msg.v : -1;
      p.vs = msg.vs && typeof msg.vs === 'object' ? msg.vs : null;
      if (p.vs && room.vehicles.has(p.vs.id) && room.vehicles.get(p.vs.id).dead) { p.vs = null; p.veh = -1; }
      return;
    case 'shot':
      if (!p.alive) return;
      room.broadcast({ t: 'shot', id: p.id, o: msg.o, v: msg.v, w: msg.w, tr: !!msg.tr }, p);
      return;
    case 'nade':
      if (!p.alive) return;
      room.broadcast({ t: 'nade', id: p.id, p: msg.p, v: msg.v }, p);
      return;
    case 'boom':
      room.broadcast({ t: 'boom', p: msg.p, r: Math.min(+msg.r || 0, 10), w: msg.w, fx: msg.fx !== false }, p);
      return;
    case 'hit': {
      const victim = room.players.get(msg.v);
      if (!victim) return;
      const w = String(msg.w || 'ar');
      if (w === 'fall' && victim !== p) return;
      if (victim !== p && victim.team === p.team) return;
      if (!p.alive && w !== 'grenade' && w !== 'rpg' && w !== 'shell') return;
      const dmg = Math.max(0, Math.min(+msg.d || 0, MAX_HIT[w] ?? 100));
      room.damage(victim === p && w === 'fall' ? null : p, victim, dmg, !!msg.h, w);
      return;
    }
    case 'vhit': {
      const id = Number.isInteger(msg.id) ? msg.id : -1;
      if (id < 0 || id > 64) return;
      const v = room.vehicle(id, msg.k);
      if (v.dead) return;
      v.hp -= Math.max(0, Math.min(+msg.d || 0, 600));
      room.broadcast({ t: 'vdmg', id, hp: Math.round(v.hp) });
      if (v.hp <= 0) {
        v.dead = true;
        room.broadcast({ t: 'vdead', id, by: p.id });
        for (const q of room.players.values()) {
          if (q.veh === id && q.alive) room.damage(p, q, 999, false, 'rpg');
        }
        setTimeout(() => {
          room.vehicles.delete(id);
          room.broadcast({ t: 'vspawn', id });
        }, 30000);
      }
      return;
    }
    case 'spawn':
      p.hp = 100;
      p.alive = true;
      return;
    default:
  }
}

const server = http.createServer((req, res) => {
  const body = JSON.stringify({
    game: 'YUKKURI STRIKE', creator: CREATOR, ok: true, protocol: PROTOCOL_VERSION,
    rooms: rooms.map((r) => ({ id: r.id, players: r.players.size, tickets: r.tickets })),
  });
  res.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'access-control-allow-origin': '*' });
  res.end(body);
});

const wss = new WebSocketServer({ server, maxPayload: 16 * 1024, perMessageDeflate: false });

wss.on('connection', (ws) => {
  const p = { id: nextId++, ws, name: 'Player', team: 0, pos: [0, 0, 0], rot: [0, 0], crouch: false, weapon: 'ar', veh: -1, vs: null, alive: true, hp: 100, k: 0, d: 0, room: null, last: Date.now(), joined: false };
  ws.on('message', (data) => {
    p.last = Date.now();
    let msg;
    try { msg = JSON.parse(data.toString()); } catch { return; }
    if (!msg || typeof msg !== 'object') return;
    if (!p.joined) {
      if (msg.t !== 'hello') return;
      if (msg.ver !== PROTOCOL_VERSION) { ws.close(4000, 'protocol mismatch'); return; }
      p.name = String(msg.name || 'Player').replace(/[\u0000-\u001f]/g, '').slice(0, 16) || 'Player';
      findRoom().add(p);
      p.joined = true;
      ws.send(JSON.stringify({ t: 'welcome', id: p.id, team: p.team, seed: MAP_SEED, tk: p.room.tickets, room: p.room.id, ver: PROTOCOL_VERSION, creator: CREATOR }));
      console.log(`[join] #${p.id} ${p.name} room=${p.room.id} team=${p.team}`);
      return;
    }
    handle(p, msg);
  });
  ws.on('close', () => {
    if (p.room) { p.room.remove(p); console.log(`[leave] #${p.id}`); }
  });
  ws.on('error', () => {});
});

setInterval(() => {
  const now = Date.now();
  for (const r of rooms) {
    for (const p of r.players.values()) {
      if (now - p.last > 20000) p.ws.terminate();
    }
    if (r.players.size > 0) r.broadcast(r.snapshot());
  }
}, 1000 / TICK_HZ);

server.listen(PORT, () => console.log(`YUKKURI STRIKE server (by ${CREATOR}) listening on :${PORT}`));

module.exports = { server, wss, rooms };
