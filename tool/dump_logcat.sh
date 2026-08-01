#!/usr/bin/env bash
# Pull the on-device diagnostic trace for the auto-capture (direct-mpv) flow.
ADB=/usr/bin/adb

echo '=== 1. CURRENT ACTIVITY ==='
"$ADB" shell dumpsys activity activities 2>/dev/null | grep -iE 'mResumedActivity|topResumedActivity' | head -2

echo
echo '=== 2. FILMKU_AUTOCAPTURE trace ==='
"$ADB" logcat -d 2>/dev/null | grep -E 'FILMKU_AUTOCAPTURE' | tail -60

echo
echo '=== 3. FILMKU_EXTRACT summary ==='
"$ADB" logcat -d 2>/dev/null | grep -E 'FILMKU_EXTRACT_SUMMARY' | tail -25

echo
echo '=== 4. FILMKU_WEBVIEW / FILMKU_MPV ==='
"$ADB" logcat -d 2>/dev/null | grep -E 'FILMKU_WEBVIEW|FILMKU_MPV' | tail -25

echo
echo '=== 5. WebView/Chrome errors during those windows ==='
"$ADB" logcat -d 2>/dev/null | grep -iE 'chromium|inappwebview|WebView' | grep -iE 'error|fail|denied|blocked' | tail -15
