#!/usr/bin/env bash
# Pull on-device evidence from the phone: which player path ran, subtitle
# outcomes, and what's on screen right now.
export ANDROID_HOME=/opt/android-sdk
export PATH=/opt/android-sdk/platform-tools:$PATH
ADB=adb
SERIAL=${1:-mrdm5povbql7guob}
PKG=com.filmku.filmku

echo "=== 1. APP RUNNING? ==="
$ADB -s "$SERIAL" shell pidof $PKG 2>&1 || echo 'not running'

echo
echo "=== 2. TOP ACTIVITY ==="
$ADB -s "$SERIAL" shell dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|topResumedActivity' | head -2

echo
echo "=== 3. FILMKU_ LOGCAT (player path + subtitles) ==="
timeout 30 $ADB -s "$SERIAL" logcat -d 2>/dev/null | grep -E 'FILMKU_' | tail -80

echo
echo "=== 4. SCREENSHOT ==="
timeout 30 $ADB -s "$SERIAL" exec-out screencap -p > /tmp/phone_screen.png 2>/dev/null
echo "screenshot: $(wc -c < /tmp/phone_screen.png 2>/dev/null) bytes"
