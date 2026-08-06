#!/usr/bin/env bash
# Check the Android emulator environment before running the e2e test.
export ANDROID_HOME=/opt/android-sdk
echo '=== AVDs ==='
/opt/android-sdk/emulator/emulator -list-avds 2>&1 | head -5
echo
echo '=== existing release apk ==='
ls -la /home/ridhoajaaa/DataD/FreeBuff/FilmKU/build/app/outputs/flutter-apk/ 2>/dev/null || echo 'NO BUILD DIR'
echo
echo '=== RAM (host) ==='
free -m | head -2
echo
echo '=== flutter ==='
command -v flutter
flutter --version 2>&1 | head -2
echo
echo '=== adb path ==='
ls -la /opt/android-sdk/platform-tools/adb 2>/dev/null || echo 'NO ADB'
echo
echo '=== FILMKU_ log markers in source ==='
grep -rn 'FILMKU_' /home/ridhoajaaa/DataD/FreeBuff/FilmKU/lib --include='*.dart' -o | sed 's/.*://' | sort -u | head -40
