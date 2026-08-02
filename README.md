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

A working default key is already embedded in `lib/core/constants/app_constants.dart`,
so `flutter run` works out of the box. To use your own key:

```bash
flutter run --dart-define=TMDB_API_KEY=your_key_here
```

Or enter it in the app: **Settings → TMDB API Key** (stored locally in Hive,
takes precedence over the build-time key).

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
   - (toggle each in **Settings → Video Sources**; see the
     [Changelog](#-changelog) for current source health — as of 2026-08 the
     2Embed domains (`2embed.cc`/`2embed.skin`) are alive, but only VidLink
     is confirmed producing a playable NATIVE stream; 2Embed.skin is
     best-effort for native and reliable via the WebView fallback)
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

## 📝 Changelog

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
