# third_party vendored packages

## flutter_inappwebview_android

Vendored copy of the `flutter_inappwebview_android` plugin, referenced from
`pubspec.yaml` via `dependency_overrides`.

**Why:** AGP 9 (used by the Flutter 3.44.x template) removed
`getDefaultProguardFile('proguard-android.txt')`. The upstream package
(1.1.3, latest at the time of vendoring) still calls it in both `debug` and
`release` build types, which fails `flutter build apk --release`. The vendored
copy carries a one-line fix:

```diff
- proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
+ proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
```

(`proguard-android-optimize.txt` is Google's recommended replacement — the old
file shipped `-dontoptimize`, which blocked R8.)

**Upgrading:** copy the new version from the pub cache into this directory,
re-apply the same one-line change, then run `flutter pub get`. See the
"Android Build Notes" section of the main `README.md`.
