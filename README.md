# YUKKURI STRIKE （yukkuri-FPS）

**制作者 / Created by: ゆっくりP**

完全無料・クロスプラットフォーム（Windows / macOS / Linux / Android / iOS）のマルチプレイ・タクティカル FPS プロトタイプです。
A free, cross-platform multiplayer tactical FPS prototype built with **Godot 4.3**, with a lightweight **Render.com** WebSocket server.

> 広告なし・課金なし / No ads, no microtransactions.

## Features / 特徴
- **Ballistics (Arma-style)**: every bullet is simulated with muzzle velocity, gravity and drag (bullet drop & travel time), adjustable zeroing (100–800 m), damage falloff, head/body hitboxes.
- **Large terrain**: 1.28 km × 1.28 km procedurally generated battlefield (deterministic seed) with towns, bases, forests, rocks, grass and water, LOD terrain chunks.
- **Destruction & vehicles (Battlefield-style)**: block-based destructible buildings with structural collapse, RPG / grenades / tank shells, tanks crush walls; drivable jeep (MG) and main battle tank (turret cannon).
- **Gunplay & movement (CoD-style)**: sprint, slide, lean, ADS, procedural recoil / sway / bob, hit markers, killfeed, polished HUD (compass, radar, tickets, objectives).
- **Conquest mode** with objectives A/B/C and tickets; offline play against AI bots.
- **Online multiplayer** via the Render.com server (`server/`), 20 Hz snapshots, server-authoritative HP/kills/tickets — see [docs/PROTOCOL.md](docs/PROTOCOL.md).
- **Controls**: keyboard & mouse, gamepad, and a **mobile virtual pad** (auto-enabled on phones/tablets).
- **9 languages**, switchable in-game: English, 日本語, 简体中文, 한국어, Español, Français, Deutsch, Português (BR), Русский.
- **Quality presets** (Low/Medium/High/Ultra) — mobile defaults to Low. All textures, models and sounds are procedural (no third-party assets except OFL fonts).

## Download / ダウンロード
Get the ZIPs from **[GitHub Releases](https://github.com/mucunsazhen959-png/yukkuri-FPS/releases)**. Each ZIP contains a bilingual `README.txt` with installation steps for every platform.
各 ZIP に、全プラットフォームの導入手順（日本語・英語）を記載した `README.txt` が同梱されています。

| Platform | File |
|---|---|
| Windows | `YukkuriStrike-vX-Windows.zip` → `YukkuriStrike.exe` |
| macOS | `YukkuriStrike-vX-macOS.zip` → `Yukkuri Strike.app` (universal) |
| Linux | `YukkuriStrike-vX-Linux.zip` → `YukkuriStrike.x86_64` |
| Android | `YukkuriStrike-vX-Android.zip` → `YukkuriStrike.apk` (arm64) |
| iOS | `YukkuriStrike-vX-iOS-Xcode.zip` → Xcode project (sign with your Apple ID) |

## Build / ビルド
Requirements: Godot 4.3 + export templates, Python 3.8+, (Android) JDK 17 + Android SDK.
```bash
python3 tools/build.py                 # exports all presets, writes dist/README.txt and ZIPs
python3 tools/build.py --targets linux,windows
python3 tools/build.py --readme-only   # README.txt only
```
**Release automation**: push a tag such as `v0.1.0` → GitHub Actions (`.github/workflows/release.yml`) builds every platform, generates `README.txt`, and attaches the ZIPs to a GitHub Release.

## Server (Render.com)
```bash
cd server && npm install && npm test && npm start   # local: ws://localhost:10000
```
Deploy: Render dashboard → **New → Blueprint** → select this repo (uses `render.yaml`). Default client URL: `wss://yukkuri-strike-server.onrender.com` (change it in the Online screen).

## Controls / 操作
PC: WASD move · Mouse look · LMB fire · RMB aim · Shift sprint · Ctrl/C crouch (slide while sprinting) · Space jump · R reload · 1-4 / wheel weapons · G grenade · F vehicle · Q/E lean · PgUp/PgDn zeroing · Tab score · Esc menu.
Touch: left stick (push fully to sprint), drag right side to look, FIRE (drag to aim while firing), AIM / JUMP / CROUCH / RELOAD / SWAP / GRENADE / USE / MENU.

## Development
```bash
godot --path .                               # run
godot --headless --path . -- --smoke-test    # automated smoke test
godot --path . -- --screenshot --out=shots   # automated screenshot tour
```

## Credits
- Game design & development: **ゆっくりP**
- Engine: [Godot Engine](https://godotengine.org) (MIT)
- Fonts: Noto Sans JP, Teko (SIL OFL 1.1)

© ゆっくりP — MIT License (see [LICENSE](LICENSE)).
