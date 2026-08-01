#!/bin/bash
# emulator_e2e.sh — ONE-SHOT end-to-end test on the Android emulator.
#
# The sandbox kills background processes when a command returns, so the
# emulator, install, launch, UI driving, logcat capture and teardown must all
# happen inside this single command.
#
# Usage: emulator_e2e.sh [movie_index]   (movie_index: 0 = first movie, default 0)
export ANDROID_HOME=/opt/android-sdk
export PATH=/opt/android-sdk/platform-tools:$PATH
ADB=/opt/android-sdk/platform-tools/adb
EMU=/opt/android-sdk/emulator/emulator
APK=/home/ridhoajaaa/DataD/FreeBuff/FilmKU/build/app/outputs/flutter-apk/app-release.apk
PKG=com.filmku.filmku

mkdir -p /tmp/e2e
rm -f /tmp/e2e/*.png /tmp/e2e/*.xml /tmp/e2e/logcat.txt

echo "### 1. START EMULATOR"
pkill -f 'emulator.*filmku' 2>/dev/null
pkill -f 'qemu.*filmku' 2>/dev/null
sleep 2
$EMU -avd filmku -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect -no-snapshot -no-metrics > /tmp/e2e/emulator.log 2>&1 &
EMU_PID=$!
echo "EMU_PID=$EMU_PID"

echo "### 2. WAIT BOOT (up to 360s)"
BOOTED=0
for i in $(seq 1 36); do
  BOOT=$($ADB -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  if [ "$BOOT" = "1" ]; then echo "BOOTED at ~$((i*10))s"; BOOTED=1; break; fi
  sleep 10
done
if [ "$BOOTED" != "1" ]; then
  echo "BOOT FAILED"; tail -20 /tmp/e2e/emulator.log
  kill $EMU_PID 2>/dev/null
  exit 1
fi

echo "### 3. INTERNET CHECK"
$ADB -s emulator-5554 shell 'ping -c 2 -W 3 8.8.8.8 2>&1 | tail -2' || echo "PING_FAIL"

echo "### 4. INSTALL APK"
$ADB -s emulator-5554 install -r "$APK" 2>&1 | tail -2

echo "### 5. CLEAR LOGCAT"
$ADB -s emulator-5554 logcat -c 2>/dev/null || true

echo "### 6. LAUNCH APP"
$ADB -s emulator-5554 shell am start -n $PKG/.MainActivity 2>&1 | head -2
sleep 12

echo "### 7. HOME SCREENSHOT + UI DUMP"
$ADB -s emulator-5554 exec-out screencap -p > /tmp/e2e/home.png 2>/dev/null
$ADB -s emulator-5554 shell uiautomator dump /sdcard/ui.xml 2>&1 | head -1
$ADB -s emulator-5554 shell cat /sdcard/ui.xml 2>/dev/null > /tmp/e2e/home_ui.xml
echo "home.png: $(wc -c < /tmp/e2e/home.png 2>/dev/null) bytes"
echo "home_ui.xml: $(wc -c < /tmp/e2e/home_ui.xml 2>/dev/null) bytes"
echo "--- any text nodes in home dump ---"
grep -oE 'text="[^"]+"' /tmp/e2e/home_ui.xml 2>/dev/null | head -20 || echo "no text nodes (Flutter semantics off)"

echo "### 8. DONE (harness OK). Keep app running briefly for evidence."
sleep 3
$ADB -s emulator-5554 logcat -d 2>/dev/null | grep -E 'FILMKU_|flutter' | tail -30 > /tmp/e2e/logcat.txt
echo "logcat lines: $(wc -l < /tmp/e2e/logcat.txt)"

echo "### 9. TEARDOWN"
kill $EMU_PID 2>/dev/null
sleep 2
echo "DONE"
