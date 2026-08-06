#!/usr/bin/env bash
# Emulator layout comparison: screenshot the mpv player at MPV_OPENED
# (layout is visible even if the stream doesn't start playing).
export ANDROID_HOME=/opt/android-sdk
export PATH=/opt/android-sdk/platform-tools:/home/ridhoajaaa/flutter/bin:$PATH
ADB=/opt/android-sdk/platform-tools/adb
EMU=/opt/android-sdk/emulator/emulator
APK=/home/ridhoajaaa/DataD/FreeBuff/FilmKU/build/app/outputs/flutter-apk/app-debug.apk
DEV=emulator-5554
PKG=com.filmku.filmku
mkdir -p /tmp/e2e

pkill -f 'GradleDaemon' 2>/dev/null; pkill -f 'kotlin.*daemon' 2>/dev/null
pkill -f 'dart.*flutter_tools' 2>/dev/null; pkill -f 'idevicesyslog' 2>/dev/null
sleep 3; sync 2>/dev/null
pkill -f 'emulator.*filmku' 2>/dev/null; pkill -f 'qemu.*filmku' 2>/dev/null
sleep 2
$EMU -avd filmku -no-window -no-audio -no-boot-anim \
  -gpu swiftshader_indirect -no-snapshot -no-metrics \
  -memory 1152 -cores 4 \
  > /tmp/e2e/emulator.log 2>&1 &
EMU_PID=$!
BOOTED=0
for i in $(seq 1 30); do
  B=$(timeout 8 $ADB -s $DEV shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  [ "$B" = "1" ] && { echo "BOOTED at ~$((i*10))s"; BOOTED=1; break; }
  sleep 10
done
[ "$BOOTED" = "1" ] || { echo BOOT_FAIL; tail -5 /tmp/e2e/emulator.log; exit 4; }

timeout 8 $ADB -s $DEV shell input keyevent 224 >/dev/null 2>&1
timeout 8 $ADB -s $DEV shell wm dismiss-keyguard >/dev/null 2>&1
timeout 8 $ADB -s $DEV shell svc power stayon true >/dev/null 2>&1
timeout 120 $ADB -s $DEV install -r "$APK" 2>&1 | tail -1
timeout 8 $ADB -s $DEV logcat -c 2>/dev/null || true
timeout 8 $ADB -s $DEV shell am start -n $PKG/.MainActivity 2>&1 | head -1

SHOT=0
for i in $(seq 1 24); do
  sleep 5
  LOGS=$(timeout 15 $ADB -s $DEV logcat -d 2>/dev/null | grep -E 'FILMKU_MPV_')
  if [ "$SHOT" = "0" ] && echo "$LOGS" | grep -q 'FILMKU_MPV_OPENED'; then
    sleep 2
    timeout 15 $ADB -s $DEV exec-out screencap -p > /tmp/e2e/emu_player.png 2>/dev/null
    echo "screenshot at OPENED: $(wc -c < /tmp/e2e/emu_player.png 2>/dev/null) bytes"
    SHOT=1
    sleep 6
    timeout 15 $ADB -s $DEV exec-out screencap -p > /tmp/e2e/emu_player2.png 2>/dev/null
    echo "screenshot +6s: $(wc -c < /tmp/e2e/emu_player2.png 2>/dev/null) bytes"
  fi
  echo "$LOGS" | grep -q 'E2E_ALL_RESULTS' && { echo 'test done'; break; }
done
[ "$SHOT" = "1" ] || { echo 'NO OPENED EVIDENCE'; timeout 30 $ADB -s $DEV logcat -d 2>/dev/null | grep FILMKU_ | tail -15; }
kill $EMU_PID 2>/dev/null
sleep 2
pkill -f 'emulator.*filmku' 2>/dev/null
echo DONE
