# FilmKU 🎬

A modern, **ad-free** movie streaming app built with **Flutter**.

FilmKU fetches movie metadata (posters, ratings, synopses, cast) from the
[TMDB API](https://www.themoviedb.org/) and plays streams inside a **native
video player** — no visible WebView, no overlay ads, no pop-ups.

> ⚠️ **Disclaimer**
> Third-party stream sources (vidsrc, gdrive player, etc.) are unofficial,
> unstable, and can disappear or change at any time. Only stream content you
> are legally entitled to watch. This project is for educational purposes.

---

## ✨ Features

- 🏠 **Home** — hero carousel (trending), popular, top rated & upcoming rows
- 🔍 **Search** — real-time search with debouncing
- 🔖 **Watchlist** — save movies locally with Hive
- ⚙️ **Settings** — TMDB API key, source toggles, extraction options
- 🎬 **Detail** — backdrop, poster, cast, similar movies
- ▶️ **Native player** — landscape, custom controls (10s skip, quality,
  subtitle selector), zero ads

## 🏗️ Architecture

Clean Architecture with Riverpod (presentation → domain → data).

```
lib/
├── core/                         # Cross-cutting concerns
│   ├── constants/                # API & app constants
│   ├── local/                    # Hive-backed settings service
│   ├── network/                  # Dio client + interceptors
│   ├── router/                   # GoRouter configuration
│   ├── theme/                    # Colors & ThemeData
│   └── utils/                    # Debouncer, formatters
└── features/movies/
    ├── domain/                   # Entities + repository contracts
    ├── data/                     # TMDB datasource, stream extractor,
    │                             #   repository impl, watchlist service
    └── presentation/             # Riverpod providers, screens, widgets
```

## 🚀 Getting Started

### 1. Install Flutter

See [docs.flutter.dev](https://docs.flutter.dev/get-started/install).

### 2. Get a TMDB API key (free)

1. Create an account at <https://www.themoviedb.org/>
2. Go to **Settings → API** and request an API key (v3 auth).

### 3. Provide the API key

There is **deliberately no default key embedded** in the app — you must
provide your own (keeps the key out of the public binary/repo). Two ways:

```bash
flutter run --dart-define=TMDB_API_KEY=your_key_here
```

or enter it in the app: **Settings → TMDB API Key** (stored locally in Hive,
takes precedence over the build-time key, no rebuild needed). Without a key
the app shows a clear "add your key in Settings" error instead of loading
movies.

### 4. Generate platform folders (if missing)

```bash
flutter create . --org com.filmku --project-name filmku
```

### 5. Platform permissions

**Android** (`android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<application ... android:usesCleartextTraffic="true" ...>
```

**iOS** (`ios/Runner/Info.plist`):

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

### 6. Run

```bash
flutter pub get
flutter run
```

## 📱 iOS (tanpa Mac & tanpa biaya)

FilmKU is 100% iOS-ready (folder `ios/`, ATS `NSAllowsArbitraryLoads` set), but
building it normally needs a Mac + Xcode. **You can do it for free, without a
Mac and without the $99/year Apple Developer fee:**

1. **Build the IPA in the cloud (free)** — push this repo to GitHub and run the
   included workflow `.github/workflows/build-ios.yml` (macOS runner, free for
   public repos). It builds `flutter build ios --release --no-codesign` and
   uploads `FilmKU-unsigned.ipa` as an artifact. No signing needed on the
   runner.
2. **Sign & install with a free Apple ID (free)** — a free Apple ID (no
   payment, just an iCloud login) can sign 3 sideloaded apps. Tools that do
   this for you:

   | Tool | Needs | Notes |
   |---|---|---|
   | **Sideloadly** | Windows/Mac + USB | Drag the IPA, enter Apple ID, install. Simplest. |
   | **AltStore** | Windows/Mac (AltServer) | Auto-refreshes signatures over Wi-Fi before expiry. |
   | **SideStore** | PC once, then on-device | Refreshes entirely on-device after initial setup. |
   | **TrollStore** | iOS 14.0–16.6.1 / 17.0 only | **Permanent** install — no 7-day re-sign. Requires a PC tool once. |
   | **Sideloader (Linux, this repo)** | Linux + USB, vendored binary | `./tool/resign_ios.sh FilmKU-unsigned.ipa you@icloud.com` — built from source, local anisette (no dead third-party servers), reuses your cert on re-sign. |

3. **The 7-day reality** — free-Apple-ID apps expire after 7 days. Sideloadly
   users re-push the IPA weekly; AltStore/SideStore auto-refresh before
   expiry. The $99 fee only buys permanent signing / App Store / TestFlight —
   nothing in the free path needs it.
4. **Re-sign after 7 days (Linux, one command)** — this repo ships a
   prebuilt Sideloader CLI (`tool/ios-sideloader/sideloader`, built from
   source because the official release crashes on 2026 Apple auth — see
   `tool/ios-sideloader/BUILD.md`) plus a wrapper script:

   ```bash
   ./tool/resign_ios.sh ~/Downloads/FilmKU-unsigned.ipa you@icloud.com
   ```

   It **reuses the certificate** Sideloader created on the first install
   (matched by public key, no revoke needed), re-provisions and reinstalls.
   First time only: enable **Developer Mode** on the iPhone (Settings →
   Privacy & Security → Developer Mode → ON → restart) — required once for
   sideloaded apps on iOS 16+.

   > 🔐 **Security:** if your Apple ID password was ever shared in a chat,
   > change it at appleid.apple.com and use an **App-Specific Password** for
   > future re-signs (appleid.apple.com → Sign-In & Security →
   > App-Specific Passwords).

> ℹ️ No iPhone at all? The same workflow can target the **simulator** by
> changing `--no-codesign` to `--simulator` — but there is no iOS simulator
> on a Linux host, so this only helps if you use a cloud Mac.
>
> ℹ️ **mpv native player on iOS:** the WebView-handoff player uses libmpv
> (`media_kit`). `media_kit_libs_android_video` in `pubspec.yaml` is
> Android-only — when building for iOS, add `media_kit_libs_ios_video` so the
> handoff player has its libmpv binaries (otherwise the iOS build compiles
> but that player has no native renderer).

## ▶️ Playback Flow (native-first, WebView last-resort)

1. **Extract natively** — `SourceAggregator` (Dio) tries to pull a direct
   `.m3u8`/`.mp4` from every enabled provider.
2. **Zero streams? Auto-capture (hidden WebView)** — if extraction finds
   nothing, `PlayerScreen` loads the first enabled provider's embed page in an
   **invisible** WebView (`HiddenStreamCapture`, `Opacity(0)+IgnorePointer`, so
   network interceptors still fire) that captures the direct media URL the
   embed player requests, then jumps **straight into the native libmpv
   player** (`media_kit`) — the user never sees a WebView or its ads.
   - Known limitation: embeds that only fetch the manifest after a user play
     *gesture* can't be auto-captured (no gesture is sent to the hidden
     WebView) and will time out after ~25s; the error screen then offers
     **“Play in WebView”** as the manual escape hatch.
3. **Manual fallback** — “Play in WebView” / “Buka di WebView (manual)” opens
   the embed in a visible in-app WebView (ad-stripped via `addUserScript`
   all-frames injection + request-level 204 blocking). If its player exposes
   a plain http(s) media URL, a **“Play natively (ad-free)”** button hands off
   to the libmpv player at the same position. If mpv fails too, the app pops
   back into the WebView so the movie keeps playing.

Diagnostics: every step logs `FILMKU_EXTRACT_*`, `FILMKU_AUTOCAPTURE_*`,
`FILMKU_WEBVIEW_*`, and `FILMKU_MPV_*` for logcat analysis.

## 🔌 Stream Source Pipeline
1. **Source Aggregator** builds embed URLs from the TMDB id:
   - `vidsrc.to`, `2embed.cc`, `vidsrc.su`, `vidlink.pro`
     (cineby pruned 2026-08 — its embed redirects to a `bulsis.net` scam
     affiliate page)
   - (toggle each in **Settings → Video Sources**; **current source health is
     data-driven** — `tool/source_health.json` holds each provider's verdict,
     `lastChecked` and notes, refreshed by
     `TMDB_API_KEY=xxx ./tool/probe_providers.sh` (reads the key from the
     environment — never hardcoded), so the README no longer carries
     hand-edited health notes per release)
2. **Direct scan** — fetch the embed HTML with Dio and regex for `.m3u8`/`.mp4`
   (follows one level of iframes, incl. `data-src` iframes).
3. **Headless extraction** — if nothing is found, a headless
   `flutter_inappwebview` loads the page invisibly and runs injected JS to
   locate the video element / HLS config, returning direct stream URLs.
   It also intercepts `fetch()`/XHR requests (`shouldInterceptRequest`),
   which is how JS/WASM players (e.g. VidLink) expose their signed `.mp4`.
4. **Native playback** — the extracted `.m3u8`/`.mp4` plays in
   `video_player` with custom controls. Ads never render.

## 🚀 Push to GitHub & build the iOS IPA (free, no Mac)

This repo is ready to push: the iOS workflow (`.github/workflows/build-ios.yml`)
builds an unsigned IPA on a free macOS GitHub Actions runner, and you install
it on your iPhone with a free Apple ID via Sideloadly/AltStore (see the iOS
section above). Secrets are protected: `android/key.properties`, `*.jks`,
`.env`, `build/` and `ios/Pods/` are all git-ignored.

### 1. Register your SSH key with GitHub (one-time)

1. Copy the public key:

   ```bash
   cat ~/.ssh/id_ed25519.pub
   ```

   (If you have no key yet: `ssh-keygen -t ed25519 -C "you@example.com"`.)

2. Open **GitHub → Settings → SSH and GPG keys → New SSH key**, paste the key,
   save. Verify: `ssh -T git@github.com` should greet `Hi <username>!`.

### 2. Create the repository (once)

- Go to <https://github.com/new>, name it `FilmKU` (or anything), keep it
  **Public** (public repos get free macOS runner minutes) or Private, do **NOT**
  check "Add a README/gitignore/license" (this repo already has them), then
  **Create repository**.

### 3. Push from this machine

```bash
cd /home/ridhoajaaa/DataD/FreeBuff/FilmKU
git remote add origin git@github.com:<USERNAME>/FilmKU.git
git push -u origin main
```

### 4. Build the IPA in the cloud

GitHub → **Actions** tab → **Build iOS (free, no Mac)** → **Run workflow** (or
it runs automatically on push). Wait ~10–15 min, download the
`filmku-ios-unsigned` artifact, then install via Sideloadly with a free Apple
ID (re-sign every 7 days, or use TrollStore on supported iOS versions for a
permanent install).

## 🧪 Checks

```bash
flutter analyze
dart format --set-exit-if-changed lib test
flutter test
```

A **CI gate** (`.github/workflows/ci.yml`) runs exactly these three on every
push to `main` and every pull request (ubuntu runner, cached Flutter).
Enable it as a required status check under GitHub → **Settings → Branches →
Branch protection rules** so a PR cannot merge while red.

## 🛠️ Android Build Notes (Troubleshooting)

Two build blockers were hit on the Flutter 3.44.x / AGP 9.0 template. If a
release build fails on a fresh machine or CI, check these first.

### 1. AGP 9 removes `proguard-android.txt` (flutter_inappwebview)

**Symptom:**

```
Build file '.../flutter_inappwebview_android-1.1.3/android/build.gradle' line: 44
> `getDefaultProguardFile('proguard-android.txt')` is no longer supported ...
```

**Cause:** AGP 9.0 removed the legacy `proguard-android.txt` (it ships
`-dontoptimize`, blocking R8). The transitive plugin
`flutter_inappwebview_android` (from `flutter_inappwebview` 6.1.5, latest) still
references it in both `debug` and `release` build types.

**Fix (permanent — applied in this repo):** a patched copy of the plugin is
vendored in `third_party/flutter_inappwebview_android/` and wired up via
`dependency_overrides` in `pubspec.yaml`, so the fix travels with the repo to
any machine/CI — no pub-cache surgery needed.

**Upstream status (checked 2026-08):** there is **no stable release** with the
fix yet, so the vendored override stays for now:

| Version | Proguard fix? |
|---|---|
| `1.1.3` (latest stable) | ❌ still `proguard-android.txt` (broken with AGP 9) |
| `1.2.0-beta.1` / `beta.2` | ❌ still `proguard-android.txt` |
| `1.2.0-beta.3` | ✅ `proguard-android-optimize.txt` (changelog: *"Fixed [Android] Upgrade to AGP 9"* #2765) |

However, adopting `1.2.0-beta.3` means moving the **whole plugin stack** to
`flutter_inappwebview` 6.2.0 beta line (`flutter_inappwebview_platform_interface
^1.4.0-beta.3`, Dart SDK ^3.8.0, Flutter >=3.32.0), which conflicts with the
main package constraint `flutter_inappwebview: ^6.1.5` → `platform_interface
^1.3.0` and is a major pre-1.0 rewrite of the most critical component (the
headless WebView stream extractor). Not worth it to delete three lines of
override.

**When `third_party/` can be removed:** once the fix ships in a **stable**
`flutter_inappwebview_android` 1.2.x (or `flutter_inappwebview` 6.2.0 stable),
drop the `dependency_overrides` + `third_party/` directory and use the official
packages. Watch the changelog:
<https://pub.dev/packages/flutter_inappwebview_android/changelog>

To upgrade the vendored copy (e.g. when upstream fixes this and you want the
official package back):

```bash
# 1. Copy the new package version into third_party/:
#    cp -r ~/.pub-cache/hosted/pub.dev/flutter_inappwebview_android-<new>/ \
#          third_party/flutter_inappwebview_android
# 2. Apply the same one-line fix, then re-run flutter pub get:
sed -i "s/getDefaultProguardFile('proguard-android.txt')/getDefaultProguardFile('proguard-android-optimize.txt')/g" \
  third_party/flutter_inappwebview_android/android/build.gradle
grep -n getDefaultProguardFile third_party/flutter_inappwebview_android/android/build.gradle
flutter pub get
```

If you'd rather patch the pub cache directly (temporary, lost on
`flutter pub cache repair` / other machines):

```bash
PLUGIN=~/.pub-cache/hosted/pub.dev/flutter_inappwebview_android-1.1.3/android/build.gradle
# (adjust the 1.1.3 in the path if the plugin version changed)
sed -i "s/getDefaultProguardFile('proguard-android.txt')/getDefaultProguardFile('proguard-android-optimize.txt')/g" "$PLUGIN"
```

### 2. Gradle daemon OOM on low-RAM machines

**Symptom:**

```
Gradle build daemon disappeared unexpectedly (it may have been killed or may have crashed)
```

(check `dmesg` for `oom-kill ... task=java`).

**Cause:** the Flutter template sets `org.gradle.jvmargs=-Xmx8G`, which is
impossible on machines with ≤8GB RAM (this project's dev machine has 7.5GB).
The kernel OOM-killer kills the Gradle daemon mid-build.

**Fix:** already applied in `android/gradle.properties` — keep the heap within
available RAM and cap the Kotlin daemon if it still OOMs:

```properties
org.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError
# If it still OOMs, also add:
# kotlin.daemon.jvmargs=-Xmx1G
# org.gradle.workers.max=2
```

### 3. Release signing (key.properties)

The release APK is signed with a dedicated keystore:

- `android/app/filmku-release.jks` + `android/key.properties` are **git-ignored**
  (`android/.gitignore` already covers `key.properties` and `*.jks`).
- `android/app/build.gradle.kts` reads the signing config from `key.properties`
  and **falls back to debug signing** when the file is missing, so CI builds
  still work — the APK just won't carry the production signature.
- Keep the keystore + password safe: losing them means you can never sign an
  update that installs over the existing app
  (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).

### 4. Android SDK on Arch (CachyOS)

Minimal CLI SDK (no Android Studio):

```bash
paru -S android-sdk-cmdline-tools-latest android-sdk-platform-tools
sudo /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager \
  'platforms;android-36' 'build-tools;36.0.0'
yes | sudo /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --licenses
sudo chown -R "$USER":"$USER" /opt/android-sdk   # Gradle needs write access
flutter doctor   # Android toolchain should be green

> Note: `sudo sdkmanager --licenses` writes licenses to `/root/.android`, while
> Gradle checks the *user's* `~/.android/licenses`. Everything works because
> the packages are already installed (AGP never auto-installs). If a future
> build asks for a missing license, run `flutter doctor --android-licenses`
> (as your user) to accept them there too.
```

---

### `2026-08-05` — v1.3.17: mini player root-cause fix (illegal Positioned) + X always pressable + relay subtitle fix

- **Mini player root cause finally found.** A probe test proved the floating
  window's `Stack > LayoutBuilder > Positioned` structure is ILLEGAL in
  Flutter (ParentDataWidget corruption) — in release builds that silently
  broke the layout: the mini player rendered mid-screen and its video surface
  could cover the whole screen with a blank/white texture that ate every
  touch (the "white 50% screen, must force-quit" bug). The overlay now
  returns a DIRECT `Positioned` (a direct child of the app-level Stack) with
  the anchor computed from `MediaQuery` size — bottom-right in every
  orientation, following rotation. Reveal is delayed 800ms (past the route
  pop) and expanding waits for the end of frame so the mini Video unmounts
  before the fullscreen Video mounts (two Videos must never share a
  controller in the same frame).
- **Close X always pressable.** The full-screen failure overlays (auto-switch
  notice + "Native playback failed") covered the always-visible top bar.
  They are now compact centered cards: the X / PiP stay usable and the video
  stays visible behind them.
- **Subtitle support through the HLS relay fixed.** WebVTT subtitle chunks
  are now served with a `text/vtt` content type (before: everything
  non-playlist was served as `video/mp2t`, which could make the player
  reject external subtitle tracks). Embedded subtitles inside the TS
  segments were already passed through untouched.
- **Diagnostics:** every session logs `FILMKU_MPV_TRACKS` with the real
  video/audio/subtitle track counts — the honest answer to "why no
  subtitles" (many 2vcdn streams carry NO subtitle track at all; the log
  proves which case you are in).
- New `test/mini_player_position_test.dart` (5 tests: portrait/landscape
  anchor, drag clamps, delta preservation). 190/190 tests pass, analyze clean.

## 📝 Changelog

### `2026-08-05` — v1.3.20: second subtitle source (SubtitleCat) — film jadul akhirnya dapat subtitle Indonesia

- **Why:** YIFY has nothing (or no Indonesian) for many older/niche movies — the
  "no subtitles" complaint for old films. Now `SubtitleDatasource` chains TWO
  free keyless sources: **YIFY first** (IMDB-id based, Indonesian→English), then
  **SubtitleCat** (`subtitlecat.com`) when YIFY has nothing.
- **SubtitleCat flow:** TMDB title + year → `index.php?search={title year}` →
  release-group detail pages (up to 5 crawled) → direct `.srt` links with the
  language in the filename (`-id.srt` Indonesian, `-en.srt` English) →
  download the raw SRT (no zip, no key, no anti-bot). Indonesian preferred,
  English fallback. Works even when the TMDB→IMDB lookup fails (title-only).
- **Live-verified 2026-08:** 12 Angry Men (1957) → Indonesian found on page 2;
  Casablanca (1942) → Indonesian found on page 3; Spider-Man: No Way Home →
  Indonesian on multiple pages. Popular movies are still served by YIFY first.
- Defensive: a 200 HTML page is never handed to the player as a subtitle;
  one dead release page never kills the chain (per-page try/catch).
- 219/219 tests pass (8 new: SubtitleCat parsers + fallback end-to-end),
  analyze clean.

### `2026-08-05` — v1.3.19: Subtitle Indonesia eksternal (YIFY, tanpa API key) — film jadul akhirnya ada teksnya

- **Akar masalah (dibuktikan di device):** stream 2Embed/2vcdn TIDAK punya
  track subtitle sama sekali — master playlist-nya 144 byte dengan NOL
  baris `#EXT-X-MEDIA`. Jadi "tidak pernah ada subtitle" bukan bug pemutar,
  melainkan stream-nya memang kosong. Bukti log: `FILMKU_MPV_TRACKS` selalu
  `subtitle=0`.
- **Fitur baru `SubtitleDatasource`:** TMDB id → IMDB id (`external_ids`) →
  YIFY subtitles (`yifysubtitles.ch/movie-imdb/{tt}`, gratis, tanpa API key)
  → pilih bahasa **Indonesia, fallback English** → download `.zip` →
  ekstrak `.srt` → render via libmpv (`SubtitleTrack.data`).
- **Fix kritikal Cloudflare:** download `.zip` YIFY ditolak 403 ("Just a
  moment…") tanpa header `Referer`. Sekarang kirim `Referer` = halaman
  detail subtitle. Dibuktikan dari laptop: UA+Referer → HTTP 200 zip asli
  39KB; UA saja → 403 challenge. Tanpa ini seluruh alur subtitle diam-diam
  gagal (`null`).
- **Filter slug:** hanya link `-yify-{id}` yang dianggap subtitle asli
  (link navigasi `/subtitles/popular` dst. diabaikan) + fallback ekstrak
  memilih file teks terbesar di dalam zip.
- **Best-effort penuh:** subtitle di-fetch di latar belakang (timeout 20s);
  kegagalan apa pun (film tidak ada di YIFY, jaringan, 403) di-swallow —
  playback TIDAK pernah terhambat. Auto-load hanya saat stream tidak punya
  track subtitle native.
- 213/213 test pass (+15 test subtitle: parser, Referer header, fallback
  bahasa, edge case slug/zip).


### `2026-08-05` — v1.3.18: replay bug fixed (stale relay URL) + subtitles auto-select

- **Replay bug fixed.** Closing a movie (X) then replaying the SAME movie
  always failed with "No playable stream found" until a force-quit. Root
  cause: the extraction result is cached for the whole app session, but a
  2Embed.skin source's `videoUrl` is a LOCAL HLS relay URL
  (`http://127.0.0.1:{port}/master.m3u8?src=…`) whose loopback port dies
  when the previous playback session ends. Replaying handed mpv a dead port
  → connection refused → the whole flow collapsed to the error screen.
  Fix: cached relay URLs are now revived at load time — re-served through a
  freshly re-bound relay (or kept as-is when the live relay already matches
  the URL's port, so the first play costs nothing). A stale URL whose CDN
  original can no longer be fetched is dropped, so the flow falls through to
  auto-capture instead of failing.
- **Subtitles now auto-select.** libmpv only auto-enables DEFAULT/forced
  subtitle tracks, and HLS subtitle variants are usually DEFAULT=NO — so
  streams that HAD subtitles never showed them. The player now auto-selects
  the first subtitle track once per open (FILMKU_MPV_SUBTRACK log), and the
  subtitle toggle selects the first track explicitly instead of
  `SubtitleTrack.auto()`. `FILMKU_MPV_TRACKS` now also logs track titles so
  the on-device syslog proves whether a stream genuinely has no subtitle
  track or the player was hiding it.
- 9 new regression tests for the relay-revive logic + URL helpers.
  **198/198 tests pass**, analyze clean.


### `2026-08-05` — v1.3.16: subtitles back (libass) + mini-player/expand/X fixes

- **Embedded subtitles finally render again.** media_kit's mpv defaults
  `sub-visibility` to NO, so every movie lost its in-stream subtitles in the
  mpv rewrite. The player now enables libass subtitle rendering (bundled
  Roboto font asset for Android), so movies with embedded subtitle tracks
  show them by default and the subtitle toggle actually toggles them.
- **Mini player always lands bottom-right.** The floating window's position
  is now computed from the Stack's own constraints (LayoutBuilder) every
  build, so it re-anchors on rotation instead of freezing at a position
  captured while the fullscreen player was still landscape (the mid-screen
  bug).
- **Tapping the mini player no longer leaves ghost audio.** The expand used
  `context.push` from the app-builder context (outside the navigator), which
  could fail silently — the window hid, the audio kept playing, and only a
  force-quit ended it. It now pushes through the global router with a
  stop() safety net on failure.
- **Close X always pressable.** The top bar (PiP, title, source, X) no
  longer auto-hides with the bottom controls — it stays visible like the
  v1.3.12 player, so closing never requires revealing hidden controls.
- **Subtitle feedback is a centered toast** (visible over the immersive
  fullscreen player) instead of a bottom SnackBar; streams without a
  subtitle track say so honestly.
- Mini-player close/play buttons enlarged (~32px touch targets).
  185/185 tests pass, analyze clean.

### `2026-08-05` — v1.3.15: mini-player position + honest subtitle/settings feedback

- **Mini player anchors bottom-right again.** It appeared mid-screen because
  the position was computed once with the LANDSCAPE size of the fullscreen
  player, then portrait rotation kicked in. The floating window now stores a
  drag delta relative to a bottom-right anchor recomputed every build, so it
  always lands at the bottom (and follows rotation while dragged).
- **Subtitle button gives honest feedback.** Most streams carry no subtitle
  track, so the toggle silently did nothing (read as broken). Now it shows a
  short "Subtitel tidak tersedia untuk stream ini." notice — but only after
  the stream actually loaded (avoids a false message while tracks are still
  being enumerated).
- **Settings sheet tells the truth about tracks.** Resolusi/Audio sections
  always render: with a single track (the common HLS case) they explain the
  quality is adaptive / uses the default track instead of showing a tap that
  does nothing; the subtitle-track section shows "tidak tersedia" when the
  stream has none. Speed is the only actively switchable option on these
  single-track streams, which is now visibly why.
- 185/185 tests pass, analyze clean.

### `2026-08-05` — v1.3.14: player preferences remembered across sessions

- **Playback speed, subtitle size and mute now persist** in the Hive-backed
  `SettingsService`. Every new movie starts with the user's last choices:
  the player applies the saved speed (mpv `setRate`), the saved subtitle
  font size (clamped to the 20–52px range) and the saved mute state on
  session start.
- Changes are saved as you make them: speed chip selection, mute toggle and
  subtitle-size slider (saved when the settings sheet closes).
- Guard added so a stale initial volume event can't flip the mute icon back
  to unmuted while a restored mute is being applied.
- New `test/player_prefs_persistence_test.dart` (defaults + round-trips).
  185/185 tests pass, analyze clean.

### `2026-08-05` — v1.3.13: iOS player features = Android (custom controls + pop-up-film mini player)

- **iOS player finally matches Android's feature set.** The built-in
  `media_kit` adaptive controls (which rendered minimal on iOS) are replaced
  by a custom full-featured controls overlay used on EVERY platform: tap to
  show/hide (auto-hide while playing), play/pause, seek bar + elapsed/total
  time, mute, subtitle on/off, and a settings sheet — playback speed
  (0.5x–2x), subtitle size (20–52px, applied live to rendered subtitles),
  video quality/resolution (when libmpv exposes multiple video tracks) and
  audio track selection.
- **"Pop up film" (mini player).** New `MiniPlayerService` owns the native
  Player/VideoController lifecycle, so the player survives the fullscreen
  route pop: the PiP button (top bar) or iOS swipe-down minimizes playback
  into a small draggable floating window visible on EVERY screen (mounted in
  `app.dart` above the Navigator); tapping it expands straight back to
  fullscreen — same Player, same position, no re-open. Closing (X / Android
  back) fully stops playback; the HLS relay now lives with the session so the
  mini player keeps pulling segments.
- **Failure-flow preserved.** Startup/silent-freeze watchdogs and the
  auto-failover-to-WebView path are untouched; minimizing a never-started
  stream is blocked so the WebView fallback still runs.
- New `test/mpv_controls_helpers_test.dart` (time formatting + settings
  presets). 181/181 tests pass, analyze clean.


### `2026-08-05` — v1.3.12: fix silent HlsRelay null-server crash — `relay=failed` on-device

- **On-device iOS syslog catch (2026-08-05):** extraction SUCCEEDED on the iPhone
  (`FILMKU_EXTRACT_TRY sourceId=two_embed_skin twoVcdnDirect=https://2vcdn.skin/stream/.../master.m3u8`)
  but logged `relay=failed` — `HlsRelay.serve()` returned null and the movie fell
  through to the WebView (spinner forever).
- **Root cause:** the reviewer's bind-after-validate ordering made `serve()` rewrite
  the master playlist BEFORE binding the loopback server; `_relayUri()` dereferenced a
  NULL `_server.port` (Null check operator on null), which the swallow-all catch
  turned into a silent null. The Linux E2E passed only because the standalone tool
  used its own inline server (bound first) — the REAL `HlsRelay.serve()` had never
  been exercised end-to-end.
- **Fix:** `serve()` binds FIRST (single-flight), then fetches + rewrites; an invalid
  master disposes the server again (no bound-but-unused leak).
- **Tests that would have caught it:** NEW `test/hls_relay_serve_test.dart` drives the
  REAL `HlsRelay.serve()` against a loopback fake CDN (master → variant → PNG-wrapped
  TS segment), asserting the relay URL is non-null and the rewritten chain serves
  clean 0x47 TS — in a binding-free file, because TestWidgetsFlutterBinding mocks
  every HTTP request with 400. Also a null-for-no-media-lines case.
- **Re-verified with the REAL relay:** `dart run tool/relay_e2e_standalone.dart`
  (now uses `HlsRelay.serve()` instead of an inline server) → `relayUrl` non-null →
  real mpv decoded h264 1728x720 + AAC, exit 0. 175/175 tests pass, analyze clean.

### `2026-08-05` — v1.3.11: 2Embed direct HLS extraction + local PNG-strip relay — THE iOS native fix

- **Root cause, finally solved with byte-level proof.** Every previous fix fought the WebView on iOS
  (shell redirects, disable-devtool, anti-frame JS-pause) because the stream was assumed to need JS.
  It never did. The 2vcdn player page (`2vcdn.skin/e/{sid}`) embeds the stream URL as a RELATIVE
  path inside a Dean-Edwards-packed script:
  `file: "/stream/{token}/{token2}/{ts}/{fileId}/master.m3u8"` — extractable over PLAIN HTTP.
- **But the m3u8 alone never played in mpv/ExoPlayer/AVPlayer**: every segment is served as a
  FAKE PNG (a constant 70-byte PNG header prepended to raw MPEG-TS — the classic
  "video-in-image" anti-leech). Verified: stripping the 70 bytes → identical bytes play in mpv
  (h264 1728x720 30fps + AAC).
- **Fix: a tiny local HLS relay (`HlsRelay`, loopback-only)**. Extraction decodes the packer
  (radix 36 — NOT the classic 62! — verified: token `d4` = index 472 = `vplayer`), gets the
  direct master.m3u8, and serves it through the relay which (1) rewrites every playlist URI to
  itself and (2) strips the PNG wrapper from every segment. mpv/media_kit sees a clean, native,
  ad-free HLS stream on 127.0.0.1 — **identical on iOS and Android, zero WebView involvement**.
- **Proven end-to-end on Linux with real mpv** (2026-08-05): extraction → relay → `mpv`
  decoded h264 + AAC, 5 frames, clean exit. 172/172 tests pass, analyze clean.
- New unit tests: jsUnescape, radixToBase (36), packer decode, stream-path regex, PNG-strip
  (70-byte wrapper / non-PNG passthrough), relay playlist rewrite. E2E tool `tool/relay_e2e_standalone.dart`
  retained for re-verification.

### `2026-08-05` — v1.3.10: neutralise 2vcdn anti-framing guard — JW player requests its m3u8 on iOS

### `2026-08-05` — v1.3.10: neutralise the 2vcdn anti-framing guard — JW player finally requests its m3u8 on iOS

- **Progress from v1.3.9 (on-device syslog):** the direct-player bypass works —
  `2embed.skin` resolves to `2vcdn.skin/e/{sid}`, the page LOADS on iOS
  (LOADSTOP fires, the `location.replace("/")` redirect is cancelled) — but
  the JW player never requests its `.m3u8`. Headless proof showed the m3u8 IS
  served when the page is FRAMED; the difference is that WKWebView **pauses
  the page's JS when a top-level navigation is initiated** (even one we later
  cancel), so `jwplayer.setup` never executes.
- **Fix:** inject a document-start user script (top frame) that overrides
  `Location.prototype.replace` to no-op the root `/` redirect *before* the
  page's own anti-framing script runs — the guard never initiates a
  navigation, so JS runs uninterrupted and the player requests the playlist
  exactly like the proven framed case. Injected in all three WebView paths
  (hidden auto-capture, visible WebView, headless extractor), keeping the
  `shouldOverrideUrlLoading` cancel as belt-and-suspenders.
- 2 new unit tests; **160/160 tests pass, analyze clean.**



### `2026-08-05` — v1.3.9: 2Embed.skin direct-player bypass — iOS finally plays natively

- **Root cause (on-device iOS syslog + headless proof):** the 2embed.skin shell
  (`/embed/movie/{id}`) is an ad landing page that JS-redirects to
  `/movie/movie/{id}` — which embeds the DEAD `2embed.cc` player. The redirect
  cancels the real player iframe (`streamsrcs → 2vcdn`) before it loads
  (NSURLError -999 in syslog), so iOS never captured a stream while Android
  won the race.
- **Fix:** resolve the shell to its direct JW-player URL (`2vcdn.skin/e/{sid}`)
  via plain HTTP (parse the shell's `data-src` swish id), load THAT page
  directly, and cancel its anti-framing `location.replace("/")` redirect in
  `shouldOverrideUrlLoading`. The JW player then serves plain `.m3u8`
  (`2vcdn.skin/stream/.../master.m3u8` — verified headless) straight into
  capture → native mpv, with no ad shell at all.
- Applied to all three paths: extraction (`TwoEmbedSkinExtractor` + headless
  extractor), hidden auto-capture, and the visible WebView fallback.
- 6 new unit tests (swish-id parse incl. entity-encoded, 2vcdn URL build,
  killer-navigation cancellation). **158/158 tests pass, analyze clean.**



### `2026-08-03` — v1.3.8: neutralise `disable-devtool` — 2Embed.skin finally captures on iOS

**On-device evidence (iOS syslog 2026-08-03):** 2embed.skin's embed + player pages
load the `disable-devtool` anti-debug script (`cdn.jsdelivr.net/npm/disable-devtool`).
In a WKWebView the library FALSE-POSITIVES "devtools opened" — iOS
`innerWidth`/`outerWidth` differ in landscape/immersive — and redirects the page
to `theajack.github.io/disable-devtool/404.html?h=...`, killing the player. The
hidden auto-capture then timed out on every provider on iOS (`NSURLErrorDomain
-999` on the 404 redirect) while Android (equal widths) never tripped it — which
is exactly why 2Embed.skin (the source that plays natively on Android) never
captured on iOS.

- **`disable-devtool` script + `theajack.github.io` 404 redirect are now
  blocked** in the hidden auto-capture WebView, the visible WebView fallback
  AND the headless extractor: the script is answered with an empty 204 and the
  redirect navigation is cancelled — the 2embed player runs normally, its
  `.m3u8` gets captured, and playback jumps straight into libmpv natively.
- New shared `embedIsDisableDevtoolUrl` guard + 2 unit tests. **153/153 pass,
  analyze clean.**

### `2026-08-03` — v1.3.7: iOS native playback root-cause fix — VidLink URLs are WebView-only, never feed them to mpv

**On-device evidence (iOS syslog 2026-08-03):** VidLink's signed URL carries an EMPTY
`headers={}` query template that the player NEVER fills (the browser itself requests
it empty — netlog-verified), and the CDN (`noir.suubmon.store`) rejects every non-
browser replay with **HTTP 428** (tested: app headers, full browser header set,
cookies, range, HTTP/1.1, HTTP/2 — all 428). libmpv can never play it; on-device
mpv reported `Failed to open` 0.5s after every open. Handing it to mpv just bounced
back into the WebView, where the iOS player sat PAUSED at 0s forever (spinner).

- **Hidden auto-capture rejects non-directly-playable URLs** (empty `headers={}`
  template) and gives up on the provider after 2 consecutive rejections (~4s),
  advancing to the NEXT provider instead of burning the budget — so on iOS the
  proven native-friendly **2Embed.skin** (the source Android's 2/2 flow captured)
  gets its shot, and VidLink (WebView-only) is skipped fast.
- **Visible WebView:** an unplayable URL no longer registers as a native stream —
  no more ghost "Play natively" handoff, no auto-handoff countdown over a
  WebView-only source, and the **"Tap to play" overlay now actually appears** for
  a paused `<video>` (it was suppressed by the bogus native-stream).
- **Ad-stripper no longer kills the play button:** the injected all-frames script
  now treats elements whose id/class contains `play`/`start`/`watch` as player
  affordances (never removed). Previously an overlay named `*-play*` was killed as
  an "ad" — leaving iOS players (which wait for a play tap) with no play button
  and a forever-spinner.
- 4 new unit tests (empty-template rejection incl. lowercase `%7b%7d`, give-up
  threshold, CDN identity normalization). **151/151 pass, analyze clean.**

### `2026-08-03` — v1.3.6: iOS release builds now log to the system log (NSLog bridge) — logcat finally works on iPhone

- **Why logcat was always empty on iOS:** `debugPrint` is a NO-OP in release
  builds (wrapped in `assert`), so every `FILMKU_*` diagnostic never reached
  the device log while playback was failing with CDN rejections.
- **Fix:** new `lib/core/utils/app_logger.dart` — `appLog()` uses plain
  `print` (works in release; visible in Android logcat + Linux terminal) and
  on iOS mirrors into the native system log (`NSLog`) via a `filmku/log`
  MethodChannel handled in `AppDelegate.swift`. All `FILMKU_MPV_*` lines now
  go through it, so `idevicesyslog` / Console.app capture them in release
  builds.
- Verified CDN rejections (2026-08, live probe with the app's exact
  headers): VidLink signed URLs → **HTTP 428 Forbidden** (403 without
  headers). v1.3.5 also shows the real mpv error on-screen in the failover
  notice.
- Version bumped to **1.3.6+1** (`pubspec.yaml` + `AppConstants.appVersion`).

### `2026-08-03` — v1.3.5: fix "Native playback failed" over a still-loading mpv + root-cause the vidlink 428

- **The full error UI can no longer render over a still-loading player.**
  Root cause: libmpv reports `playing` while the stream is STILL LOADING
  (core not idle), so an error arriving with zero position progress parked
  the "Native playback failed" UI on top of the loading player. "Started"
  is now defined ONLY by the position advancing past zero; every
  never-started failure (startup timeout / open error / any error at zero
  position) takes the compact "beralih ke pemutar cadangan…" auto-failover
  into the WebView — never the full error UI. Mid-play stalls (real progress
  happened, then froze) still show the full UI with Retry.
- **The real CDN error is now shown** under the failover notice (e.g. the
  HTTP 428 from a signed vidlink URL) so users see WHY before the WebView
  takes over — no more infinite mystery loading.
- **Root cause of vidlink's stuck loading, verified live (2026-08):** the
  direct URL is a signed TEMPLATE with an empty `headers={}` query param the
  JS player fills right before requesting; replayed outside the page the CDN
  answers **HTTP 428 Forbidden** (403 plain) — even the browser hits 428 on
  many requests. New `isDirectPlayableUrl` filter rejects empty
  `headers=` templates in BOTH the Dio scan and the headless capture, so the
  pipeline falls straight through to the WebView path, which captures the
  FILLED request URL mpv can actually replay (the proven-working route) —
  skipping the doomed 428 detour.
- **WebView→mpv handoff now carries the browser session**: the handed-off
  stream includes the WebView's cookies for the media host as a `Cookie`
  header (best-effort), so cookie-gated CDNs accept it in mpv.
- 7 new unit tests (template filter + stall-routing + cookie header).
  Version bumped to **1.3.5+1** (`pubspec.yaml` + `AppConstants.appVersion`).

### `2026-08-03` — v1.3.4: Detail cast chips separated from the glass info panel (no more cloudy glass-in-glass)

- **Glass-in-glass fixed on iOS Detail.** The "Top Cast" section (title + chips)
  now renders in its OWN sliver, OUTSIDE the liquid-glass info panel. The cast
  chips blur the raw dark background instead of the panel — no more double-
  blur cloudiness. Android visuals unchanged (flat column, same split).
- Version bumped to **1.3.4+1** (`pubspec.yaml` +
  `AppConstants.appVersion`).

### `2026-08-03` — v1.3.3: grid scroll-stress tests prove glass grids stay lazy & clean

- **New `test/grid_scroll_perf_test.dart`** (2 widget tests) that actually
  exercise the iOS glass grid under load, not just audit it:
  1. **Laziness proof** — a 60-movie `GridView.builder` of glass `MovieCard`s
     builds only the visible row (`find.byType(MovieCard)` ≪ 60); eager
     building (the real scroll killer) would fail this instantly.
  2. **Clean-scroll proof** — scrolls deterministically to the last row and
     asserts no layout overflow / exceptions were raised (the test framework
     fails automatically otherwise) and that off-screen cards are recycled
     (card #0 leaves the tree; card #59 is present).
- Version bumped to **1.3.3+1** (`pubspec.yaml` +
  `AppConstants.appVersion`).

  > **Honesty note:** these tests prove *structural* health (lazy building,
  > no overflow during scroll, recycling) — they do **not** measure frame
  > time. Real smoothness numbers need an on-device
  > `flutter run --profile` + DevTools Performance timeline.

### `2026-08-03` — v1.3.2: grid scroll perf hardening for glass cards (iOS)

- **Perf audit of the glass grid.** Verified the stack is already scroll-safe
  by design: cards use the lightweight shader tier (standard, 5–10× faster
  than `BackdropFilter` and safe while scrolling), grids are lazy
  (`GridView.builder`), and all `GlassContainer`s share one grouped layer
  instead of each creating its own backdrop.
- **Hardened it so it stays fast.** Each iOS `MovieCard` now pins
  `quality: GlassQuality.standard` explicitly (widget-level quality wins over
  any inherited premium layer, so a future glassy screen can't silently make
  grids heavy). Each card also carries a keyed `RepaintBoundary` as
  defense-in-depth on top of the list delegate's own per-item boundaries —
  neighbour image loads / hero animations repaint only that card.
- **Perf-regression guards.** `test/movie_card_glass_test.dart` now asserts
  the card glass is pinned to `standard` quality AND that the keyed
  `RepaintBoundary` still exists on iOS (would fail if either is removed).
- Version bumped to **1.3.2+1** (`pubspec.yaml` +
  `AppConstants.appVersion`).

### `2026-08-03` — v1.3.1: liquid glass on movie cards & detail cast (iOS)

- **Movie cards are now glass.** Every `MovieCard` (Home rows, Search grid,
  Watchlist grid) wraps in a shader-based `GlassContainer` on iOS — the
  frosted rounded rim frames the poster + title + rating, so the whole movie
  wall reads as one glass system. Android keeps the classic flat card.
  Verified platform-split by `test/movie_card_glass_test.dart` (iOS:
  `GlassContainer` present; Android: absent).
- **Detail cast chips are glass.** Each cast member in the Detail screen's
  "Top Cast" row sits in a REAL liquid-glass chip (avatar + name + role),
  matching the glass info panel above; the row gets a touch more height so
  the chips breathe. Android untouched.
- Version bumped to **1.3.1+1** (`pubspec.yaml` +
  `AppConstants.appVersion`).

### `2026-08-03` — v1.3.0: doubled Home tab fixed, more liquid glass, mpv startup auto-failover (no dead-end error over loading player)

- **Doubled Home tab in the floating glass bar fixed (root cause).**
  `GlassTabBar.bottom` renders a selected-variant layer OVER the unselected
  layer for the tabs adjacent to the indicator. The Home tab was the only one
  with a DISTINCT `activeIcon` (`home_rounded` over `home_outlined`) — the two
  different glyphs overlapped and looked visibly DOUBLED, while Search (same
  glyph both states) looked fine. Watchlist/Settings sit outside the
  indicator's affected range, so they never doubled. Fix: dropped `activeIcon`
  from ALL tabs — the same icon renders in both layers, the overlap is
  invisible, and selection is still shown by the indicator pill + selected
  color + per-tab glow. (`app_shell.dart`)
- **More liquid glass (iOS only).** Beyond the existing header / tab bar /
  search field / detail panel / watchlist empty state:
  - **Settings** — the Stream Extraction toggles and Video Sources list now
    render as REAL glass grouped sections
    (`GlassGroupedSection` + `GlassListTile` + trailing `Switch`), the iOS-26
    grouped-table look (Android keeps Material `SwitchListTile`).
  - **Section titles** — MovieListRow titles (Popular / Top Rated / Upcoming
    on Home, Similar Movies on Detail) sit in small glass chips.
  - **Search** — empty state and "no results" cards are now glass.
  - **Home setup banner** — the "TMDB API Key missing" banner is a real
    `GlassContainer` instead of the hand-rolled frosted approximation.
- **mpv startup dead-end fixed (iOS: "movie only loads, then error over it").**
  When the direct-extraction URL never starts (signed CDN URLs need the
  WebView's session), the screen used to park on the full "Native playback
  failed" error UI over a still-loading player, requiring a manual tap. Now:
  - `MpvPlayerScreen` shows a brief "Stream tidak dapat dimulai — beralih ke
    pemutar cadangan…" notice (1.5s) and **auto-pops with `failed=true`** —
    no dead-end error UI.
  - `PlayerScreen` re-arms auto-handoff on the **first** mpv failure: the
    WebView fallback captures the URL it actually plays (proven to work in
    mpv) and hands it back to the native player. A **second** failure keeps
    auto-handoff disabled so the user stays in the WebView (no infinite
    mpv ↔ WebView bounce). Tested via
    `PlayerScreen.shouldReArmAutoHandoff` + `failoverNoticeDuration`.
- Version bumped to **1.3.0+1** (`pubspec.yaml` + `AppConstants.appVersion`).

### `2026-08-02` — v1.2.1: iOS native playback fixed (CDN headers), real liquid glass on every screen, Watchlist tab unified, neutral (no-blue) iOS theme

- **iOS playback root cause fixed: mpv now sends CDN HTTP headers.** The signed
  2embed/vidlink stream URLs return `403` to a header-less request — mpv opened
  `Media(url)` with NO `Referer`/`Origin`/`User-Agent`, so on iOS (where the
  extraction/CDN chain differs from Android) playback never started and the
  screen failed with "Native playback failed" → "Back to WebView", and even
  the WebView stayed on cover + loading. New `PlayerScreen.buildStreamHeaders()`
  builds `{User-Agent, Referer: embed page, Origin: scheme://authority}` and
  `MpvPlayerScreen` passes them via `Media(url, httpHeaders: …)` — applies to
  ALL playback paths (direct extraction, hidden auto-capture, WebView handoff).
  Covered by `test/player_headers_test.dart`.
- **Visible WebView now nudges play too.** The manual WebView fallback now
  injects the same `embedAutoPlayNudgeScript` as the hidden capture (clicks
  play affordances + calls `video.play()`), so iOS players that wait behind a
  play-button overlay no longer stay stuck on cover + spinner forever.
- **Real liquid glass on EVERY screen (not just the tab bar).** Home header
  banner, Search field, Detail info panel, Watchlist empty state and Settings
  rows now use the shader-based `GlassContainer` / `GlassTextField` /
  `GlassListTile` from `liquid_glass_widgets` on iOS — replacing the old
  hand-rolled BackdropFilter approximations. (Verified render-safe on Skia in
  `test/lgw_spike_test.dart`.)
- **Tab labels unified across platforms.** iOS tab 3 was "Favorite"; Android
  was "Watchlist". Both are now **Watchlist** with bookmark icons — no more
  platform drift.
- **No more blue.** The iOS theme accent (`#4DE1FF` aqua / `#7C6BFF` violet) is
  replaced with a neutral light-gray (`#E8E8EA`) / mid-gray (`#9E9EA8`) on a
  graphite-black base — dark gray, not blue. Tab bar glow/indicator, header
  icon and section titles follow. `tool/analyze_ios_golden.py` updated to
  check neutral-light pixels instead of aqua.

### `2026-08-02` — engineering hardening: resign retry (rate-limit), bump_version.sh, CI gate, no default TMDB key, data-driven source health

- **`tool/resign_ios.sh` retries transient Apple rate-limits.** Live installs
  hit an intermittent `ssl connect failed` right after login (DeveloperSession
  OK, then the certificate-generation request dies — a flaky provisioning
  endpoint, not a script bug; a retry a minute later succeeds). The whole
  Sideloader run now loops up to `$MAX_ATTEMPTS` (default 3) with doubling
  backoff, so a flaky Apple answer no longer fails the install. Tunables:
  `FILMKU_RESIGN_MAX_ATTEMPTS`, `FILMKU_RESIGN_BACKOFF`.
- **New `tool/bump_version.sh`** — bumps the version in BOTH places that must
  stay in sync: `version:` in `pubspec.yaml` and `AppConstants.appVersion`.
  `--major` / `--minor` / `--patch` / `--build` (default `--build`); a version
  bump resets the `+N` build number to `1`. Run it before every release so the
  installed version is always identifiable (Settings → About).
- **CI gate** — new `.github/workflows/ci.yml` runs `dart format --set-exit-if-changed`,
  `flutter analyze` and `flutter test` on every push to `main` and every PR.
  Make it a required status check in GitHub branch protection so a PR cannot
  merge while red.
- **No default TMDB API key.** The embedded default key is removed from
  `lib/core/constants/app_constants.dart` — you must provide your own key
  (build-time `--dart-define` or runtime Settings, stored in Hive). Keeps the
  key out of the public binary and repo. README updated.
- **Data-driven source health.** New `tool/source_health.json` holds each
  provider's verdict / `lastChecked` / notes; `tool/probe_providers.sh`
  rewrites it on every run. The README's Stream Source Pipeline now points at
  the file instead of carrying hand-edited health notes per release.

### `2026-08-02` — iOS v1.1.0: mpv direct-play (no WebView detour), real liquid glass v2, swipe-dismiss fullscreen, resign fix

**🎯 iOS stream flow fixed at the root ("finding stream → play webview" → "→ mvp").**
On-device evidence: on iOS the extraction usually **succeeds** (unlike Android),
then the old `_initPlayer` tried `video_player` (AVPlayer), which rejects these
CDN streams (403/428 signed URLs) → error → "Play in WebView" detour every
time. The only native player proven on both platforms is libmpv
(`media_kit`), so **every direct extraction URL now plays straight in mpv**
(`player_screen._initPlayer` → `/mpv-player`), exactly like the proven WebView
handoff path. iOS is now identical to Android: `finding stream → mvp`. The
`video_player`/`CustomVideoControls` UI path was removed (it never worked
on-device for these sources). The **"Browser headers (experimental)"**
setting is gone too — it only fed the deleted `video_player` path
(`buildStreamHeaders`), so it had become a no-op; removed together with its
4 tests. (If a future native engine ever needs custom headers again,
`buildStreamHeaders` can be resurrected from git history.)

- **Swipe-down to dismiss fullscreen** (iOS only) — new
  `widgets/player_swipe_dismiss.dart` wraps the mpv + WebView players: drag
  down past 140px (or fling down) exits fullscreen with the player translating
  with the finger; release below threshold springs back. No more killing the
  app from the background to leave fullscreen. Non-iOS platforms are a
  pass-through (Android keeps the system back button). Honest caveat: over
  the WebView's native platform view (WKWebView) the gesture may be consumed
  by the web content itself — swipe-dismiss reliably fires on the overlay
  button/chrome region; on the mpv player (pure Flutter) it works over the
  whole surface.
- **Real liquid glass v2** (`app_shell.dart`) — beyond the old simple blur:
  - **Saturation boost** on the whole iOS shell body
    (`ColorFiltered` saturation 1.3) so the frosted capsule picks up vivid,
    saturated color from the content behind it — the iOS 26 liquid-glass look;
  - **specular highlight that follows the touch** (radial white sheen at the
    finger position via `Listener` + `_SpecularPainter`);
  - **luminous edge glow** (outer white rim `BoxShadow`) + **top rim
    highlight** line + brighter hairline border; active pill gets an aqua glow.
- **`resign_ios.sh` buffering bug fixed** — it ran Sideloader through
  `| tee log`, but Sideloader (D/std.stdio) **full-buffers** when stdout is a
  pipe, so the `Apple ID:` prompt never reached the log and `wait_for()`
  timed out (the reason the 2026-08-02 install had to be driven manually in
  tmux). It now runs Sideloader directly in the tmux pane (pty → line
  buffered) and polls `tmux capture-pane`; `remain-on-exit` keeps the pane
  alive so the final `InstallComplete` marker is readable.
- **Versioning convention:** version bumped to **1.1.0+2** (`pubspec.yaml` +
  `AppConstants.appVersion` shown in Settings → About). From now on **every
  update bumps the version** so you can always tell which build is installed
  (check Settings → About, or the IPA's CFBundleShortVersionString).

**Verification:** `flutter analyze` clean, full suite pass, iOS goldens
regenerated (glass v2 changes the pixels), `tool/analyze_ios_golden.py` PASS.

### `2026-08-02` — iOS liquid-glass UI verified: golden tests + live-preview flag + capsule overflow fix

Verifying the iOS UI on a Linux host (no simulator, iPhone not always
connected) is now automated:

- **`FILMKU_FORCE_IOS_UI=true` dart-define (debug only)** — forces the iOS
theme + floating glass capsule on any platform, so the real iOS UI can be
previewed on Linux:
  `flutter run -d linux --dart-define=FILMKU_FORCE_IOS_UI=true`.
- **Golden tests** (`test/ios_ui_golden_test.dart`) render the shell at iPhone
  14 logical size (390×844): iOS liquid-glass golden, Android classic golden
  (contrast), and a geometry test proving the floating capsule **never covers
  scrolled content** (last row ends 28px above the capsule thanks to the 110px
  iOS bottom padding). `test/flutter_test_config.dart` loads real
  Roboto/MaterialIcons from the SDK cache so goldens show real glyphs
  (fail-safe Ahem fallback with a notice).
- **`tool/analyze_ios_golden.py`** + **`tool/check_live_ios_screenshot.py`** —
  pixel-verify the capsule renders (aqua accent band) and differs from the
  Android shell; the latter scans a screenshot of the live Linux run.
- **Real bug found & fixed:** the golden test caught `_GlassTabItem`'s inner
  Column overflowing ~2.6px under real fonts (RenderFlex — this would also
  overflow on a real iPhone). Fixed: pill margin 10→6, icon 22→21, gap 3→2,
  `mainAxisSize.min`.

**Verification:** `flutter analyze` clean, full suite **111/111 pass** (incl.
the 3 new tests), live Linux run boots the forced-iOS UI. No real-iPhone
screenshot on this host (no simulator; iPhone not connected at test time) —
after the next iOS build, open the app on the iPhone and check the floating
glass bar + that content scrolls clear of it.

### `2026-08-02` — iOS: native-first extraction fix (interception flags) + liquid-glass UI

**Why iOS always fell back to WebView (root cause, verified in package source):**
on Android `shouldInterceptRequest`/`shouldInterceptFetchRequest`/
`shouldInterceptAjaxRequest` fire by default, so the hidden auto-capture sees the
stream URL and jumps straight into the native mpv player (`sumber 2/2 → mvp`).
On iOS `flutter_inappwebview_ios` defaults **fetch/ajax interception to `false`**
and the classic `shouldInterceptRequest` isn't implemented in the iOS native
classes — so the hidden capture never saw a URL, timed out, and every movie fell
back to the visible WebView (`finding stream → play in webview → mvp`).

- **Fix:** new shared builder `lib/core/webview/capture_webview_settings.dart`
  (`buildCaptureWebViewSettings()`), which sets
  `useShouldInterceptRequest`/`Fetch`/`Ajax` **explicitly `true`** (with a
  `captureEnabled` switch to turn them off where capture isn't wanted). Wired
  into **all three** WebViews: the hidden auto-capture
  (`hidden_stream_capture.dart`), the visible fallback
  (`webview_player_screen.dart`) and the headless extractor
  (`stream_source_datasource.dart` — both `extract()` and
  `runSanityCheckOnce()`). iOS now captures natively like Android; the WebView
  remains a manual last-resort only.
- **New iOS-only liquid-glass UI** (Android untouched):
  - `AppTheme.ios` in `lib/core/theme/app_theme.dart` — translucent dark
glass surfaces, blurred scrims, iOS accent; `lib/app.dart` picks it via
`defaultTargetPlatform == iOS`.
  - `app_shell.dart` is now platform-aware: on iOS a **floating glass capsule
tab bar** (Home / Search / Favorite / Settings — Instagram-style, `extendBody`
+ `BackdropFilter` blur + active gradient pill) replaces the classic Material
bottom bar; the 4 tab screens get iOS bottom padding (110) so content isn't
hidden behind the floating capsule, and `HomeScreen` gets a glass header variant.
- **Tests:** `test/capture_webview_settings_test.dart` (interception flags
  on/off), `test/app_shell_test.dart` (iOS glass capsule vs Android Material
  bottom nav, tab switching) using a `withPlatform()` try/finally pattern to
  avoid the `debugAssertAllFoundationVarsUnset` invariant failure in this
  Flutter version.

**Verification:** `flutter analyze` clean, full suite **108/108 pass**.
On-device iPhone retest still pending (install via Sideloader — expect
`sumber 2/2 → mvp` directly, no WebView detour). If the iOS hidden capture
still times out, the next suspect is a media-loader-fetched manifest (not
`fetch()`/XHR), which JS-bridge interception can't see.

### `2026-08-02` — iOS sideload tooling: Sideloader binary + `resign_ios.sh`

First-ever **successful free-Apple-ID install of FilmKU on a real iPhone**
(no Mac, no $99/year account, Linux host):

- **Root cause found**: both AltServer-Linux v0.0.5 (bundled ldid from 2022
  crashes on modern Mach-O — `ldid.cpp _assert: end >= size - 0x10`) and the
  official **Sideloader `1.0-pre4` release** (Sep 2024; crashes silently right
  after 2FA on 2026 Apple auth) fail on current Apple servers.
- **Fix**: built [Dadoum/Sideloader](https://github.com/Dadoum/Sideloader)
  from source (`main`, checked 2026-07-31) with **LDC 1.34.0** (newer LDC
  fails with `objc_opt_isKindOfClass` — CI uses 1.34.0), a `libxml2.so.2`
  soname shim (CachyOS ships `.so.16`), and the exact CI recipe
  (`dub build -b release-debug --compiler=ldc2 --arch x86_64-linux-gnu
  :cli-frontend`). Result vendored (stripped 45MB → 5.8MB) at
  `tool/ios-sideloader/sideloader` + `tool/ios-sideloader/BUILD.md`.
- **New `tool/resign_ios.sh`** — one-command re-sign/install via the
  vendored binary (tmux-driven, handles 2FA, reuses the existing cert so the
  **7-day expiry** is a one-liner to refresh; see iOS section step 4).
- `tool/sideload_ios.sh` marked **DEPRECATED** (AltServer ldid path broken);
  `AltServerData/` (leftover `.p12` certs) added to `.gitignore`.
- Verified end-to-end: `DeveloperSession created` → cert issued → IPA signed
  → `100/100 InstallComplete` → `com.filmku.filmku` confirmed on device.

### `2026-08-02` — auto-handoff WebView→mpv, cap-2 capture, blank-white fix, early-abort CDN, iOS deps

All four changes were driven by on-device logcat evidence (user testing on a
Xiaomi/MIUI device, 2026-08-01/02). Every step below logs `FILMKU_*` markers
that are verified compiled into the release binary by `tool/build_verify.sh`.

1. **Auto-handoff WebView → mpv (no taps needed).** When the visible WebView
   shows stable playback (3 consecutive advancing position probes ≈6s), a
   chip counts down "Pindah ke player native: 5…" and then **automatically**
   hands the URL + position to the native libmpv player. If mpv fails, the
   app pops back to the WebView with auto-handoff **disabled** (no loop).
2. **Auto-capture capped at 2 providers** (`maxAutoCaptureProviders = 2`,
   `limitAutoCaptureCandidates`). Logcat showed the hidden capture always
   burned the full 40s + 4×20s = 120s per movie even when a CDN was ISP-
   blocked and failing within ~7s. Cap + trimmed budgets (30s first, 20s
   second) cut the worst-case wait to ~50s. Logs:
   `FILMKU_AUTOCAPTURE_TRUNCATE`.
3. **Blank-white-screen fix.** The cap-2 kept `vidsrc_to` (ISP-blocked CDN) +
   `two_embed` (2embed.cc serves `about:blank` in the user's region) — after
   both timed out, the visible WebView auto-opened 2embed.cc's blank page =
   white screen. Fixes: registry reordered to reliability order
   `[vidlink, two_embed_skin, vidsrc_to, two_embed, vidsrc_su]`; the timeout
   path now opens the **first (best-ranked)** candidate; WebView probes for
   blank pages (`about:blank`/empty body) and auto-failovers to the next
   provider after 3 blank probes (~6s, only counted after load completes);
   closing the WebView without a stream also failovers. Logs:
   `FILMKU_WEBVIEW_BLANK`, `FILMKU_WEBVIEW_BLANK_FAILOVER`.
4. **Early CDN abort.** A repeated network-level error
   (`CANNOT_CONNECT_TO_HOST` / `HOST_LOOKUP` / `CONNECTION_ABORTED` / …) on
   the **same** non-static, non-ad URL aborts the current provider after 3
   failures (≈7s of ~3s retries) instead of the full budget — static assets
   and ad/tracker hosts are excluded so a working provider with dead ad
   networks is never aborted. Logs: `FILMKU_AUTOCAPTURE_CDN_FAIL`,
   `FILMKU_AUTOCAPTURE_EARLY_ABORT`.
5. **iOS dependencies.** `media_kit_libs_ios_video ^1.1.4` added so the mpv
   player has its libmpv binaries on iOS (previously Android-only). The iOS
   unsigned build is done free in the cloud via
   `.github/workflows/build-ios.yml` (macOS runner) — see the iOS section.

**Verification:** `flutter analyze` clean, full suite **101/101 pass** (incl.
new `test/hidden_stream_capture_test.dart` — 16 early-abort tests), release
APK built + installed, signature `CN=FilmKU`, all `FILMKU_*` diagnostics
verified in `libapp.so`.

### `2026-08-01` — media_kit (libmpv) native player + direct auto-capture flow

**Root cause found via on-device logcat (evidence, not a guess):**

| Logcat evidence | Meaning |
|---|---|
| `FILMKU_WEBVIEW_CAPTURE` → `master.m3u8?token=JWT` (CDN `illimitableinkwell.site`) | ✅ Network capture works on device — the WebView hands off a real signed HLS URL |
| `FILMKU_PLAYER_INIT_ERROR` → `MediaCodecVideoRenderer error ... video/mp2t, video/avc, 640x268, format_supported=YES` | ❌ The m3u8 **was downloaded by ExoPlayer** — what crashes is the device's **hardware MediaCodec decoder** on this MPEG-TS stream |

The stream itself is healthy (verified with `tool/probe_stream.sh`: `master.m3u8`
serves 640p/1280p/1920p variants, segments fetch HTTP 200 from the device's
IP). So "no playable stream" on-device was **never** a CDN/session/TLS
rejection — the hardware decoder on this device cannot decode the stream, and
ExoPlayer has no software-decode fallback.

**Solution: swap the native engine to `media_kit` (libmpv)** — libmpv
automatically falls back to **software decoding** when hardware decode fails:

- `pubspec.yaml`: added `media_kit ^1.1.11`, `media_kit_video ^1.2.4`,
  `media_kit_libs_android_video ^1.1.5`; `main.dart` calls
  `MediaKit.ensureInitialized()`.
- New `lib/features/movies/presentation/screens/mpv_player_screen.dart`
  (`MpvPlayerScreen`) + `/mpv-player` route: opens the handed-off stream,
  seeks to the captured position, surfaces stream errors in a "Back to
  WebView" failure UI, pops `true` on failure / pops the whole player on
  normal close.
- **Direct auto-capture flow (no visible-WebView-first):** when extraction
  finds nothing, `PlayerScreen` loads the first enabled provider's embed page
  in an **invisible** WebView (`HiddenStreamCapture`,
  `Opacity(0)+IgnorePointer`, shared core in
  `widgets/stream_capture_core.dart`) and jumps **straight into the libmpv
  player** once the direct URL is captured. The visible WebView is now a
  manual last-resort only.
- Diagnostics: `FILMKU_MPV_*` (OPEN/OPENED/ERROR/FAILED/CLOSED_NORMAL) and
  `FILMKU_AUTOCAPTURE_*` (BEGIN/OPEN/USERSCRIPT_ADDED/CAPTURED/ADBLOCK/
  TIMEOUT/OK) logs.

**Verification:** `flutter analyze` clean, full suite **64/64 pass**, release
APK **99.5MB** (libmpv adds ~40MB; packaged for arm64/armv7/x86_64),
signature `CN=FilmKU`, installed on device, binary contains all
`FILMKU_AUTOCAPTURE_*` / `FILMKU_MPV_*` strings.

> ℹ️ **iOS:** `media_kit_libs_android_video` is Android-only — add
> `media_kit_libs_ios_video` for the mpv player on iOS (see the iOS section).

### `2026-08-01` — WebView anti-iklan + native handoff ("Play natively")

The WebView fallback was the reliable path but rendered the source's overlay
ads and could show a stale "failed to load" error over the playing video.
Fixes (all in `webview_player_screen.dart` + `player_screen.dart`):

- **Ad-blocking at the network level** — `onShouldInterceptRequest` answers
  known ad/tracker hosts (`doubleclick`, `googlesyndication`, `popads`,
  `applovin`, `taboola`, …) with an empty 204 so their scripts never reach
  the page; `onShouldOverrideUrlLoading` cancels main-frame navigations to
  ad landing pages (the "tap anywhere → ad" hijack). `onCreateWindow`
  already blocked popup/popunder windows. Pure `isAdHost()` helper — tested.
- **Error overlay bug fixed** — `shouldSurfaceLoadError` now requires the
  failed request URL to equal the original embed URL (previously any
  main-frame error surfaced, so a frame hijacked to a dead ad page covered
  the still-playing video with a fake "failed to load … retry").
- **⚡ Native handoff ("Play natively (ad-free)")** — the WebView is proven
  to run the source's player on-device, so it now polls the page's `<video>`
  element (`currentSrc` + `currentTime` via JS). When the embed player
  exposes a plain http(s) `.m3u8`/`.mp4` (not MSE `blob:`), a button appears;
  tapping it pops the WebView and hands the URL + position to the native
  `video_player`, which resumes playback **ad-free at the same spot**.
  `PlayerScreen.buildSourceFromWebViewResult` + `_initPlayer(startAt:)`.
- Unit tests: `test/webview_fallback_test.dart` grew to **23 tests** (ad-host
  allow/block, native-candidate filter incl. `blob:`/empty/self rejection,
  WebView→native source building, URL-matched error surfacing). Full suite
  passes, `flutter analyze` clean.

> If the embed uses MSE (`blob:`), no button appears and the (now ad-blocked)
> WebView remains the player — correct and safe.

### `2026-08-01` — New source: 2Embed.skin (revived 2Embed ecosystem)

Exhaustive live probing (2026-08-01, 12+ candidates) found most sources dead:
`vidbinge.dev`, `movie-web` (000), `embedder.net` (hijacked to a gambling
site), `filmxy.one` (empty shell), `api.vidsrc.dev` (FingerprintJS anti-bot),
`vidsrc.nl` (scam redirect to `bulsis.net`), `vidsrc.xyz`/`.su`/`.to`
(dead/empty). The **only source verified alive** was the revived 2Embed
ecosystem: both `https://www.2embed.skin/embed/movie/{tmdbId}` and the legacy
`2embed.cc` URL return HTTP 200 with the correct movie title (trending
`969681` → "Spider-Man: Brand New Day (2026)", classic `155` → "The Dark
Knight (2008)").

- New `TwoEmbedSkinExtractor` (`sourceId: two_embed_skin`, label
  "2Embed.skin") registered in `SourceAggregator.extractors` right after its
  sibling `TwoEmbedExtractor` — both domains are kept as separate toggles so
  one region-blocked/rotated domain never kills the source.
- The `.skin` embed page serves the player via a `data-src` iframe
  (`streamsrcs.2embed.cc/swish?id=...`) — a pattern the existing pipeline
  already follows (`_iframeDataSrcRegex`), so no new scraping logic needed.
- Unit tests: 2 in `test/stream_capture_test.dart` (buildEmbedUrl + registry
  order), 1 in `test/webview_fallback_test.dart` (fallback picks
  `two_embed_skin` when earlier providers are disabled). Full suite:
  **54/54 pass**, `flutter analyze` clean, APK release built + installed
  (signature `CN=FilmKU`, binary contains `2Embed.skin` strings,
  `lastUpdateTime` on device updated).

> ⚠️ Honest caveat: the 2Embed player (`/swish`) is JS-rendered and did not
> emit any `.m3u8`/`.mp4` within 30s of autoplay-allowed headless probing —
> treat it as best-effort for NATIVE extraction; its verified-alive embed
> page is the reliable part (used by the visible WebView fallback).

### `2026-08-01` — Browser headers experiment (native playback for VidLink)

Standalone probe first (`tool/vidlink_header_probe.py` — kept as a dev tool):
a fresh signed VidLink `.mp4` was extracted with headless chromium, then
fetched with different header combinations to see what the CDN demands:

| Headers sent | CDN response |
|---|---|
| none | HTTP 403 Forbidden |
| `Referer` | HTTP 403 Forbidden |
| `Referer` + `Origin` | HTTP 403 Forbidden |
| `Referer` + `Origin` + mobile UA (full browser set) | HTTP 428 Precondition Required |

**Conclusion:** the 403 → 428 progression shows VidLink's CDN is **not**
satisfied by headers alone — a real browser TLS fingerprint / session context
is also required (urllib's TLS fingerprint ≠ Chrome's, so it still gets
rejected). The only definitive test is on-device with the actual ExoPlayer
stack, so this is implemented as an **opt-in experiment**:

- New setting **"Browser headers (experimental)"** (`SettingsService
  keyBrowserHeaders`, default **off**) — toggled in Settings → Stream
  Extraction. When on, `PlayerScreen._initPlayer` passes
  `httpHeaders:` to `VideoPlayerController.networkUrl` (non-nullable in
  `video_player` 2.13.0, so `const <String, String>{}` when off).
- New `PlayerScreen.buildStreamHeaders(VideoSource)` — sends the app's
  mobile `User-Agent` + `Accept: */*`, plus `Origin`/`Referer` derived from
  the source's `embedUrl` (guarded with `hasScheme && hasAuthority` because
  `Uri.origin` throws on scheme-less URIs).
- Unit tests: 4 new tests in `test/webview_fallback_test.dart` (UA+Accept
  always, Origin/Referer derivation, omitted when embedUrl null/unparseable).
  Full suite: **46/46 pass**, `flutter analyze` clean.

**Expected outcome:** even with this on, VidLink may still refuse native
playback (TLS fingerprint) — the WebView fallback player remains the
reliable path. If a source *does* play natively with headers on, that source
no longer needs the WebView fallback.

### `2026-08-01` — Build `02:01` (release APK)

**Unified stream filtering across all extraction paths** — the Dio fast-scan
path now uses the same `shouldCaptureUrl` guard as the headless WebView path,
closing the last false-positive gap (reviewer finding):

- `_HttpPageScanner._videoUrlRegex` now captures the **whole URL token** (up to
  a quote/space/angle-bracket delimiter) instead of stopping at the first
  `.m3u8`/`.mp4` substring. A lazy match truncated `https://cdn.com/a.m3u8/b.ts`
  to `a.m3u8` — a mid-path segment URL that looked playable but wasn't.
- `scan()` filters every candidate through
  `StreamSourceDataSource.shouldCaptureUrl`, so mid-path segment URLs
  (`a.m3u8/b.ts`), script/CSS bundles (`hls.m3u8.min.js`, `player.css`) and
  query-only matches (`/redirect?to=video.m3u8`) are rejected everywhere —
  direct scan, nested-iframe scan and headless extraction alike.
- Unit tests: `test/stream_capture_test.dart` grew to **21 tests** covering
  `.js`/`.css` rejection, m3u8+query/fragment acceptance, mid-path rejection,
  case-insensitivity and edge cases. Full suite: **28/28 pass**, `flutter
  analyze` clean.
- Binary verification (`libapp.so`): new full-token regex tail compiled in,
  old lazy regex gone, all 5 sources present, 4 dead sources absent,
  signature `CN=FilmKU, O=FilmKU, C=ID`.

**Earlier extraction fixes (included in this build):**

- `shouldInterceptRequest` + `shouldInterceptAjaxRequest` +
  `shouldInterceptFetchRequest` on the headless WebView — captures
  `fetch()`/XHR requests that `onLoadResource` misses on Android, the root
  cause of "no playable stream" on device.
- `StreamSourceDataSource.shouldCaptureUrl` — path-based `.m3u8`/`.mp4`
  filter (query/fragment/trailing-slash aware) shared by capture, headless
  candidate filtering and the Dio scan.
- **VidLink** (`vidlink.pro`) added as a 5th source; it exposes a signed
  `.mp4` only after JS/WASM decrypt, so it relies on headless extraction
  (confirmed producing a playable stream 2026-08-01).
- Dead sources pruned: `vidsrc.me`, `databasegdriveplayer.xyz`,
  `multiembed.mov`, `embed.su` removed.

> ⚠️ **Source health (checked 2026-08-01):** of the 5 sources, only **VidLink**
> is confirmed producing a playable stream right now. `Cineby` returns HTTP
> 200 but renders a parked page (unrelated tarot-quiz ads, no player);
> `2Embed` serves an `about:blank` iframe with error markers; `VidSrc.su`
> serves an empty shell; `VidSrc.to` redirects to a live `vsembed.ru` chain
> with no visible video yet. The app tries all 5 and uses
> whatever plays — but if you see "no playable stream" on a specific movie,
> try another title before judging the build.

### `2026-08-01` — HTML-entity-decode for extracted URLs (HTTP 502-class fix)

Defensive fix found while investigating a VidLink 502: some CDNs sign their
`.mp4` URLs with `&amp;` in the query string (HTML-entity-encoded `&`). Passing
that literal `&amp;` to the CDN breaks the signature → HTTP 502 / "no playable
stream" even though the extracted URL was real.

- New `StreamSourceDataSource.decodeHtmlEntities()` — a **single-pass** regex
  (`&(#x?[0-9a-fA-F]+|amp|lt|gt|quot|apos|nbsp);`) via `replaceAllMapped`, so a
  literal `&amp;lt` decodes to `&lt` and never double-decodes to `<` (the bug
  chained `replaceAll` calls would have). Handles named entities and numeric
  decimal/hex (`&#38;`, `&#x26;`) with a codepoint guard; early-returns when
  the URL has no `&`.
- Applied in **all four extraction paths**: `scan()` (Dio raw-HTML regex),
  `scanIframes()` (decode before `baseUri.resolve`, so relative srcs with
  entities resolve correctly), the `capture()` closure (network interception:
  `onLoadResource` / `shouldInterceptRequest` / `Ajax` / `Fetch`) and
  `_runDomProbe` (headless DOM probe).
- Unit tests: `test/stream_capture_test.dart` grew to **28 tests** covering the
  `&amp;` 502 fix, single-pass correctness (`&amp;lt;` → `&lt;`), other named
  entities (`&apos;`/`&nbsp;`), numeric decimal/hex, unknown entities
  untouched, and no-`&` fast path. Full suite: **42/42 pass**, `flutter
  analyze` clean.

### `2026-08-01` — WebView fallback player (play when ExoPlayer cannot)

Research (2026) confirmed that nearly every free embed source now serves its
stream behind browser-context protections — blob URLs / MediaSource decrypt,
Cloudflare challenges, TLS fingerprinting or session cookies. VidLink is the
only source still producing content, but its signed `.mp4` is unusable by the
native `video_player` (ExoPlayer) because the CDN requires a real browser.

**Fix:** a **WebView fallback player** — when native playback fails, the error
screen now offers **"Play in WebView"**, which loads the source's embed page
in an in-app `flutter_inappwebview` (landscape + immersive, close button,
loading/error states). The source's own player has the browser context needed
for the signed URL, so the movie plays.

- New screen `webview_player_screen.dart` + `/webview-player` route
  (`WebViewPlayerArgs` via `state.extra`).
- `player_screen.dart`: on `_initPlayer` failure (or no playable source), the
  error view shows a `Play in WebView` action for any source with an
  `embedUrl`, preferring the source that was actually attempted.
- `error_view.dart`: new optional `secondaryLabel`/`onSecondary` params,
  rendered as a filled button with a "May show source ads" hint.

> ⚠️ **Trade-off:** WebView mode renders the source's overlay ads and player
> UI — this deliberately deviates from the app's ad-free native design and
> exists purely as a fallback when native playback is impossible.

**Verification:** `flutter analyze` clean, full suite **28/28 pass**.

---

## 📄 License

MIT — for educational use. You are responsible for the content you stream.
