#!/usr/bin/env bash
# libass on Android needs the bundled Roboto font
# (PlayerConfiguration.libassAndroidFont). If the asset is missing from the
# release APK, embedded subtitles silently never render.
export ANDROID_HOME=/opt/android-sdk
APK=/home/ridhoajaaa/DataD/FreeBuff/FilmKU/build/app/outputs/flutter-apk/app-release.apk

echo '=== Roboto font in release APK? ==='
unzip -l "$APK" 2>/dev/null | grep -i 'roboto' || echo 'NO ROBOTO IN APK !!!'

echo
echo '=== font asset in pubspec.yaml ==='
grep -n -A 8 'fonts:' /home/ridhoajaaa/DataD/FreeBuff/FilmKU/pubspec.yaml | head -15

echo
echo '=== assets section in pubspec ==='
grep -n -B 2 -A 6 'assets:' /home/ridhoajaaa/DataD/FreeBuff/FilmKU/pubspec.yaml | head -20

echo
echo '=== libass config in code ==='
grep -rn 'libass' /home/ridhoajaaa/DataD/FreeBuff/FilmKU/lib --include='*.dart' | head -5
