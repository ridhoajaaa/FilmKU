#!/usr/bin/env bash
# Install the FilmKU release APK (with VidNest native extraction) to the
# connected Android phone, then verify + launch.
export ANDROID_HOME=/opt/android-sdk
export PATH=/opt/android-sdk/platform-tools:$PATH
ADB=adb
SERIAL=${1:-mrdm5povbql7guob}
APK=/home/ridhoajaaa/DataD/FreeBuff/FilmKU/build/app/outputs/flutter-apk/app-release.apk
PKG=com.filmku.filmku

echo "=== 1. DEVICE ==="
$ADB -s "$SERIAL" get-state 2>&1
$ADB -s "$SERIAL" shell getprop ro.product.model 2>&1

echo
echo "=== 2. CURRENTLY INSTALLED VERSION (if any) ==="
$ADB -s "$SERIAL" shell dumpsys package $PKG 2>/dev/null | grep -E 'versionName|lastUpdateTime' | head -3 || echo 'not installed'

echo
echo "=== 3. FREE SPACE ON PHONE ==="
$ADB -s "$SERIAL" shell df -h /data 2>/dev/null | tail -1

echo
echo "=== 4. INSTALL (replace, allow downgrade) ==="
timeout 300 $ADB -s "$SERIAL" install -r -d "$APK" 2>&1 | tail -3

echo
echo "=== 5. VERIFY ==="
$ADB -s "$SERIAL" shell dumpsys package $PKG 2>/dev/null | grep -E 'versionName|versionCode' | head -2 || echo 'NOT INSTALLED'

echo
echo "=== 6. LAUNCH ==="
$ADB -s "$SERIAL" shell am start -n $PKG/.MainActivity 2>&1 | head -2
