#!/usr/bin/env python3
"""YUKKURI STRIKE build & packaging script.  Created by ゆっくりP.

Exports every platform preset with Godot, generates a bilingual README.txt
(English / 日本語) and produces GitHub-Release-ready ZIP files in ./dist.

Usage:
    python3 tools/build.py                       # all targets available on this OS
    python3 tools/build.py --targets linux,windows,android
    python3 tools/build.py --readme-only         # just write dist/README.txt
Environment:
    GODOT   path to the Godot 4.3 editor binary (default: "godot")
    GODOT_ANDROID_KEYSTORE_DEBUG_PATH / _USER / _PASSWORD   (Android signing)
"""
from __future__ import annotations

import argparse
import datetime as _dt
import os
import platform
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
DIST = ROOT / "dist"
CREATOR = "ゆっくりP"
TITLE = "YUKKURI STRIKE"
REPO = "https://github.com/YukkuriP/yukkuri-FPS"

TARGETS = {
    "windows": {"preset": "Windows", "out": "windows/YukkuriStrike.exe", "label": "Windows"},
    "linux": {"preset": "Linux", "out": "linux/YukkuriStrike.x86_64", "label": "Linux"},
    "macos": {"preset": "macOS", "out": "macos/YukkuriStrike.zip", "label": "macOS"},
    "android": {"preset": "Android", "out": "android/YukkuriStrike.apk", "label": "Android"},
    "ios": {"preset": "iOS", "out": "ios/YukkuriStrike.ipa", "label": "iOS-Xcode"},
}


def project_version() -> str:
    text = (ROOT / "project.godot").read_text(encoding="utf-8")
    m = re.search(r'config/version="([^"]+)"', text)
    return m.group(1) if m else "0.0.0"


def readme_text(version: str, included: list[str]) -> str:
    date = _dt.date.today().isoformat()
    files = "\n".join(f"  - {f}" for f in included) if included else "  (see GitHub Releases)"
    return f"""\
================================================================================
  {TITLE}  v{version}
  Free cross-platform multiplayer tactical FPS (prototype)
  完全無料 クロスプラットフォーム・マルチプレイ FPS（プロトタイプ）

  Created by / 制作者 : {CREATOR}
  Repository / 配布元 : {REPO}
  Build date / ビルド日 : {date}
================================================================================

Files in this package / 同梱ファイル:
{files}

This game is 100% free: no ads, no microtransactions.
本作は完全無料です（広告・課金要素は一切ありません）。

--------------------------------------------------------------------------------
 [EN] ENGLISH
--------------------------------------------------------------------------------

1. WINDOWS (10 / 11, 64-bit)
   1) Extract the ZIP (right click > "Extract All...").
   2) Double-click "YukkuriStrike.exe".
   3) If Windows SmartScreen shows "Windows protected your PC", click
      "More info" > "Run anyway" (the build is not code-signed).
   Requirements: GPU with Vulkan 1.0+ (most GPUs from 2016 or newer).

2. macOS (10.15 Catalina or newer, Intel & Apple Silicon)
   1) Extract "YukkuriStrike.zip" -> you get "Yukkuri Strike.app".
   2) Drag the app into the "Applications" folder.
   3) The app is not notarized: the first time, right-click the app >
      "Open" > "Open". If macOS still blocks it, open
      System Settings > Privacy & Security and press "Open Anyway",
      or run in Terminal:  xattr -dr com.apple.quarantine "/Applications/Yukkuri Strike.app"

3. LINUX (x86_64, glibc 2.28+)
   1) Extract the ZIP.
   2) Make it executable:  chmod +x YukkuriStrike.x86_64
   3) Run:  ./YukkuriStrike.x86_64
   Requirements: Vulkan drivers (Mesa 20+ or proprietary NVIDIA/AMD).

4. ANDROID (8.0+, arm64 device)
   1) Copy "YukkuriStrike.apk" to the phone (or download it on the phone
      from GitHub Releases).
   2) Open the APK. When asked, allow "Install unknown apps" for your
      browser / file manager.
   3) Tap "Install", then "Open". Touch controls are enabled automatically.

5. iOS / iPadOS (12.0+)
   Apple does not allow installing unsigned apps directly, so iOS is
   distributed as an Xcode project ("YukkuriStrike-iOS-Xcode.zip").
   1) On a Mac with Xcode 15+, extract the ZIP and open "YukkuriStrike.xcodeproj".
   2) Select the target > "Signing & Capabilities" > choose your Apple ID
      team (a free Apple ID works for personal devices).
   3) Connect your iPhone/iPad, select it as the run destination and press Run.
   4) On the device: Settings > General > VPN & Device Management >
      trust your developer certificate.
   (TestFlight / App Store distribution requires an Apple Developer account.)

HOW TO PLAY
   Main menu > "Offline Battle" : play immediately against AI bots.
   Main menu > "Online"         : join the Render.com server. The free server
                                  sleeps when idle; the first connection may
                                  take up to ~50 seconds.
   Game mode: CONQUEST - capture objectives A / B / C. Holding more objectives
   drains the enemy's tickets. A team reaching 0 tickets loses.

PC CONTROLS
   WASD move | Mouse look | Left click fire | Right click aim (ADS)
   Shift sprint | Ctrl / C crouch (while sprinting: slide) | Space jump
   R reload | 1-4 / mouse wheel switch weapon | G grenade | F enter/exit vehicle
   Q / E lean | PageUp / PageDown zeroing | Tab scoreboard | Esc menu
   Gamepads (XInput) are also supported.

TOUCH CONTROLS (smartphone / tablet)
   Left half: virtual stick (push fully forward to sprint)
   Right half: drag to look | FIRE button (drag while firing to aim)
   AIM, JUMP, CROUCH, RELOAD, SWAP, GRENADE, USE and MENU buttons.

LANGUAGE
   Settings > Language. English, 日本語, 简体中文, 한국어, Español, Français,
   Deutsch, Português (BR), Русский. Can be changed during a match (Esc).

SELF-HOSTING THE SERVER
   The server is in the "server" folder of the repository (Node.js 18+).
   Deploy to Render.com with the included "render.yaml" (New > Blueprint),
   then enter  wss://<your-service>.onrender.com  in the Online screen.

--------------------------------------------------------------------------------
 [JA] 日本語
--------------------------------------------------------------------------------

1. Windows（10 / 11、64bit）
   1) ZIP を展開します（右クリック →「すべて展開」）。
   2) 「YukkuriStrike.exe」をダブルクリックして起動します。
   3) 「Windows によって PC が保護されました」と表示された場合は
      「詳細情報」→「実行」を押してください（コード署名なしのため）。
   動作環境: Vulkan 1.0 以上に対応した GPU。

2. macOS（10.15 Catalina 以降、Intel / Apple Silicon 両対応）
   1) 「YukkuriStrike.zip」を展開すると「Yukkuri Strike.app」が出てきます。
   2) 「アプリケーション」フォルダへドラッグします。
   3) 公証（Notarization）されていないため、初回はアプリを右クリック →
      「開く」→「開く」を選びます。それでも開けない場合は
      「システム設定」→「プライバシーとセキュリティ」→「このまま開く」、
      またはターミナルで次を実行します:
      xattr -dr com.apple.quarantine "/Applications/Yukkuri Strike.app"

3. Linux（x86_64、glibc 2.28 以降）
   1) ZIP を展開します。
   2) 実行権限を付与:  chmod +x YukkuriStrike.x86_64
   3) 起動:  ./YukkuriStrike.x86_64
   動作環境: Vulkan ドライバ（Mesa 20 以降、または NVIDIA/AMD 公式ドライバ）。

4. Android（8.0 以降、arm64 端末）
   1) 「YukkuriStrike.apk」をスマートフォンへコピーします
      （または端末のブラウザで GitHub Releases からダウンロード）。
   2) APK を開き、「提供元不明のアプリのインストール」を許可します。
   3) 「インストール」→「開く」。タッチ操作は自動で有効になります。

5. iOS / iPadOS（12.0 以降）
   Apple の制限により署名なしアプリを直接インストールできないため、
   iOS 版は Xcode プロジェクト（YukkuriStrike-iOS-Xcode.zip）で配布します。
   1) Xcode 15 以降の入った Mac で ZIP を展開し「YukkuriStrike.xcodeproj」を開きます。
   2) ターゲット →「Signing & Capabilities」で自分の Apple ID のチームを選択します
      （個人端末なら無料の Apple ID で可）。
   3) iPhone / iPad を接続し、実行先に選んで「Run（▶）」を押します。
   4) 端末側で「設定」→「一般」→「VPN とデバイス管理」から
      デベロッパ証明書を信頼してください。
   （TestFlight / App Store 配布には Apple Developer Program が必要です）

遊び方
   メインメニュー →「オフライン対戦」: AI ボットとすぐに対戦できます。
   メインメニュー →「オンライン」    : Render.com のサーバーに接続します。
     無料サーバーは休止状態から起動するため、初回接続に最大 50 秒ほど
     かかる場合があります。
   ゲームモード: コンクエスト。拠点 A / B / C を占領すると敵の残存戦力
   （チケット）が減少します。チケットが 0 になったチームの負けです。

PC 操作
   WASD 移動 | マウス 視点 | 左クリック 射撃 | 右クリック エイム（ADS）
   Shift ダッシュ | Ctrl / C しゃがみ（ダッシュ中はスライディング）| Space ジャンプ
   R リロード | 1〜4 / ホイール 武器切替 | G 手榴弾 | F 乗車 / 降車
   Q / E リーン | PageUp / PageDown ゼロイン調整 | Tab スコア | Esc メニュー
   ゲームパッド（XInput）にも対応しています。

タッチ操作（スマートフォン / タブレット）
   画面左半分: バーチャルスティック（いっぱいまで倒すとダッシュ）
   画面右半分: ドラッグで視点操作 | 射撃ボタン（押しながらドラッグでエイム）
   ADS・ジャンプ・しゃがみ・リロード・武器切替・手榴弾・乗降・メニュー ボタン。

言語設定
   「設定」→「言語」から変更できます（試合中も Esc メニューから変更可能）。
   English / 日本語 / 简体中文 / 한국어 / Español / Français / Deutsch /
   Português (BR) / Русский

サーバーを自分で立てる場合
   リポジトリの「server」フォルダ（Node.js 18 以降）を、同梱の
   「render.yaml」を使って Render.com にデプロイ（New → Blueprint）し、
   オンライン画面で  wss://<サービス名>.onrender.com  を入力してください。

--------------------------------------------------------------------------------
 CREDITS / クレジット
--------------------------------------------------------------------------------
   Game design & development / 企画・開発 : {CREATOR}
   Engine / エンジン : Godot Engine 4.3 (MIT License) - https://godotengine.org
   Fonts / フォント  : Noto Sans JP, Teko (SIL Open Font License 1.1)
   All sounds, textures and models are procedurally generated in-game.
   効果音・テクスチャ・モデルはすべてゲーム内でプロシージャル生成しています。

   (c) {CREATOR}
================================================================================
"""


def ensure_android_settings() -> None:
    """Point Godot's editor settings at ANDROID_HOME / JAVA_HOME (needed by CI)."""
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    java = os.environ.get("JAVA_HOME")
    if not java and shutil.which("java"):
        java = str(Path(os.path.realpath(shutil.which("java"))).parent.parent)
    if not sdk or not java:
        return
    if platform.system() == "Darwin":
        cfg_dir = Path.home() / "Library/Application Support/Godot"
    elif platform.system() == "Windows":
        cfg_dir = Path(os.environ.get("APPDATA", str(Path.home()))) / "Godot"
    else:
        cfg_dir = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "godot"
    cfg_dir.mkdir(parents=True, exist_ok=True)
    f = cfg_dir / "editor_settings-4.3.tres"
    text = f.read_text(encoding="utf-8") if f.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    for key, val in (("export/android/android_sdk_path", sdk), ("export/android/java_sdk_path", java)):
        line = f'{key} = "{val}"'
        if re.search(rf"^{re.escape(key)} = .*$", text, re.M):
            text = re.sub(rf"^{re.escape(key)} = .*$", line, text, flags=re.M)
        else:
            text = text.rstrip("\n") + "\n" + line + "\n"
    f.write_text(text, encoding="utf-8")


def run_godot(godot: str, preset: str, out: Path) -> bool:
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [godot, "--headless", "--path", str(ROOT), "--export-release", preset, str(out)]
    print("[build] $", " ".join(cmd), flush=True)
    proc = subprocess.run(cmd, capture_output=True, text=True)
    log = (proc.stdout or "") + (proc.stderr or "")
    for line in log.splitlines():
        if ("ERROR" in line or "error" in line) and "mesh_get_surface_count" not in line:
            print("   ", line)
    ok = proc.returncode == 0 and (out.exists() or out.with_suffix("").exists() or any(out.parent.iterdir()))
    print(f"[build] {preset}: {'OK' if ok else 'FAILED'}")
    return ok


def zip_dir(src_items: list[tuple[Path, str]], dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path, arc in src_items:
            if path.is_dir():
                for f in sorted(path.rglob("*")):
                    if f.is_file():
                        info = zipfile.ZipInfo.from_file(f, arc + "/" + f.relative_to(path).as_posix())
                        if os.access(f, os.X_OK):
                            info.external_attr = 0o755 << 16
                        with open(f, "rb") as fh:
                            z.writestr(info, fh.read(), zipfile.ZIP_DEFLATED)
            else:
                info = zipfile.ZipInfo.from_file(path, arc)
                if os.access(path, os.X_OK) or arc.endswith((".x86_64", ".sh")):
                    info.external_attr = 0o755 << 16
                with open(path, "rb") as fh:
                    z.writestr(info, fh.read(), zipfile.ZIP_DEFLATED)
    print(f"[dist] {dest.relative_to(ROOT)} ({dest.stat().st_size / 1e6:.1f} MB)")


def default_targets() -> list[str]:
    t = ["windows", "linux", "macos", "android"]
    if platform.system() == "Darwin":
        t.append("ios")
    else:
        t.append("ios")  # Xcode project export works on any host
    return t


def main() -> int:
    ap = argparse.ArgumentParser(description=f"{TITLE} build script (by {CREATOR})")
    ap.add_argument("--targets", default=",".join(default_targets()))
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    ap.add_argument("--readme-only", action="store_true")
    ap.add_argument("--skip-export", action="store_true", help="package existing ./build output")
    args = ap.parse_args()
    version = project_version()
    DIST.mkdir(exist_ok=True)
    if args.readme_only:
        (DIST / "README.txt").write_text(readme_text(version, []), encoding="utf-8")
        print("[dist] README.txt written")
        return 0
    targets = [t.strip() for t in args.targets.split(",") if t.strip()]
    built: dict[str, Path] = {}
    if "android" in targets:
        ensure_android_settings()
    for t in targets:
        if t not in TARGETS:
            print(f"unknown target {t}", file=sys.stderr)
            return 2
        out = BUILD / TARGETS[t]["out"]
        if args.skip_export:
            if out.exists() or (t == "ios" and out.parent.exists() and any(out.parent.iterdir())):
                built[t] = out
            continue
        if out.parent.exists():
            shutil.rmtree(out.parent)
        if run_godot(args.godot, TARGETS[t]["preset"], out):
            built[t] = out
    if not built:
        print("nothing was built", file=sys.stderr)
        return 1
    names = {t: f"YukkuriStrike-v{version}-{TARGETS[t]['label']}.zip" for t in built}
    readme_all = readme_text(version, list(names.values()))
    readme_path = DIST / "README.txt"
    readme_path.write_text(readme_all, encoding="utf-8")
    license_path = ROOT / "LICENSE"
    for t, out in built.items():
        tmp_readme = BUILD / f"README-{t}.txt"
        tmp_readme.write_text(readme_text(version, [names[t]]), encoding="utf-8")
        items: list[tuple[Path, str]] = [(tmp_readme, "README.txt")]
        if license_path.exists():
            items.append((license_path, "LICENSE.txt"))
        if t == "ios":
            items.append((out.parent, "YukkuriStrike-iOS"))
        else:
            for f in sorted(out.parent.iterdir()):
                if f.suffix != ".idsig":
                    items.append((f, f.name))
        zip_dir(items, DIST / names[t])
    bundle = [(readme_path, "README.txt")] + [(DIST / n, n) for n in names.values()]
    zip_dir(bundle, DIST / f"YukkuriStrike-v{version}-AllPlatforms.zip")
    print(f"[done] {TITLE} v{version} by {CREATOR}: {', '.join(built)}")
    missing = [t for t in targets if t not in built]
    if missing:
        print(f"[warn] not built: {', '.join(missing)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
