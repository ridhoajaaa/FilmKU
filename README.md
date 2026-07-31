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

## 🔌 Stream Source Pipeline

1. **Source Aggregator** builds embed URLs from the TMDB id:
   - `vidsrc.to`, `vidsrc.me`, `databasegdriveplayer.xyz`, SuperEmbed
2. **Direct scan** — fetch the embed HTML with Dio and regex for `.m3u8`/`.mp4`
   (follows one level of iframes).
3. **Headless extraction** — if nothing is found, a headless
   `flutter_inappwebview` loads the page invisibly and runs injected JS to
   locate the video element / HLS config, returning direct stream URLs.
4. **Native playback** — the extracted `.m3u8`/`.mp4` plays in
   `video_player` with custom controls. Ads never render.

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

## 📄 License

MIT — for educational use. You are responsible for the content you stream.
