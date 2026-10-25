# YUKKURI STRIKE network protocol (v1)

Created by **ゆっくりP**. Transport: WebSocket (text frames, compact JSON), server in `server/index.js`.

Authority model: clients simulate their own movement and detect their own hits; the server
owns HP, kills, tickets and vehicle HP, clamps damage per weapon, and relays world events.
Snapshots are broadcast at 20 Hz; clients send their state at 20 Hz and interpolate remotes.

## Client → server
| t | fields | meaning |
|---|---|---|
| `hello` | `name`, `ver` | join (first message) |
| `st` | `p[3]`, `r[yaw,pitch]`, `c`, `w`, `v`, `a`, `vs?` | own state (+ driven vehicle state) |
| `shot` | `o[3]`, `v[3]`, `w`, `tr` | fired projectile (relayed for visuals) |
| `hit` | `v`, `d`, `h`, `w` | damage dealt to player `v` |
| `vhit` | `id`, `d`, `k`, `w` | damage dealt to vehicle `id` (kind `k`) |
| `boom` | `p[3]`, `r`, `w`, `fx` | explosion / destruction (deterministic on all clients) |
| `nade` | `p[3]`, `v[3]` | grenade thrown (visual) |
| `spawn` | – | respawned |
| `ping` | `c` | latency probe |

## Server → client
| t | fields |
|---|---|
| `welcome` | `id`, `team`, `seed`, `tk[2]`, `room`, `ver`, `creator` |
| `snap` | `pl[] {id,n,tm,p,r,c,w,v,a,hp,k,d}`, `vs[]`, `tk[2]` |
| `shot` / `nade` / `boom` | relayed with shooter `id` |
| `dmg` | `v`, `by`, `hp`, `d` |
| `kill` | `v`, `by`, `w`, `h` |
| `vdmg` / `vdead` / `vspawn` | vehicle `id`, `hp` / `by` |
| `leave` | `id` |
| `end` | `winner` |
| `pong` | `c` |

The map is generated deterministically from `seed`, so building destruction stays in sync by
replaying `boom` events (block removal + collapse are deterministic).
