#!/bin/bash
# pull_logcat_evidence.sh — tarik bukti logcat dari HP untuk analisis
export ADB=/opt/android-sdk/platform-tools/adb

echo "=== 1. ADB DEVICES ==="
timeout 10 $ADB devices

echo
echo "=== 2. INSTALLED BUILD (lastUpdateTime) ==="
timeout 15 $ADB shell dumpsys package com.filmku.filmku 2>/dev/null | grep -iE 'lastUpdate|versionName' | head -3

echo
echo "=== 3. FILMKU_AUTOCAPTURE TRACE (full) ==="
timeout 20 $ADB logcat -d 2>/dev/null | grep -E 'FILMKU_AUTOCAPTURE' | tail -120

echo
echo "=== 4. FILMKU_EXTRACT / EXTRACT_SUMMARY ==="
timeout 20 $ADB logcat -d 2>/dev/null | grep -E 'FILMKU_EXTRACT' | tail -60

echo
echo "=== 5. FILMKU_WEBVIEW / FILMKU_MPV / MPV ==="
timeout 20 $ADB logcat -d 2>/dev/null | grep -E 'FILMKU_WEBVIEW|FILMKU_MPV|FILMKU_PLAYER|mpv' | tail -40

echo
echo "=== 6. SANITY / HEADLESS / TRY / SUMMARY 4-layer ==="
timeout 20 $ADB logcat -d 2>/dev/null | grep -E 'FILMKU_SANITY|FILMKU_HEADLESS|FILMKU_TRY|FILMKU_SUMMARY|FILMKU_CAPTURED|FILMKU_LOADSTART|FILMKU_LOADSTOP|FILMKU_RECVERROR|FILMKU_NUDGE|FILMKU_USERSCRIPT' | tail -100

echo
echo "=== 7. ANY CRASH ==="
timeout 20 $ADB logcat -d 2>/dev/null | grep -iE 'FATAL|AndroidRuntime' | grep -i filmku | tail -10
echo "(kosong = tidak crash)"

echo
echo "=== 8. WEBVIEW / Chromium errors ==="
timeout 20 $ADB logcat -d 2>/dev/null | grep -iE 'chromium|webview|exoplayer|MediaCodec' | grep -iE 'error|fail|exception' | tail -20

echo
echo "=== DONE ==="
