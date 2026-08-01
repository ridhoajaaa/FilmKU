#!/bin/bash
# emulator_test_movie.sh — ONE-SHOT full movie-play test on the emulator.
#
# Drives the real release APK: home → tap hero movie → detail → tap Play →
# wait for hidden auto-capture (polling, early-exit) → dump FILMKU_* logcat +
# screenshots → teardown. All in ONE command because the sandbox kills
# background processes when a command returns.
#
# Hardened for CI-like use:
#   - every adb call has a timeout so a hung device never blocks the run
#   - screen is woken + keyguard dismissed + kept on (no-window headless)
#   - navigation is VERIFIED (screenshot md5) and retried with alternate
#     coordinates if a tap misses
#   - logcat is polled for CAPTURED / all-exhausted instead of a fixed wait
#   - exit code reflects evidence (0=captured, 2=failure reproduced,
#     3=navigation failed, 4=infra error)
export ANDROID_HOME=/opt/android-sdk
export PATH=/opt/android-sdk/platform-tools:$PATH
ADB=/opt/android-sdk/platform-tools/adb
EMU=/opt/android-sdk/emulator/emulator
APK=${APK:-/home/ridhoajaaa/DataD/FreeBuff/FilmKU/build/app/outputs/flutter-apk/app-release.apk}
PKG=com.filmku.filmku
DEV=emulator-5554

# Tap coordinate presets (1080x2400 / dpi 420, density 2.625)
# hero carousel ~y 249-905; detail Play ~y 1255
declare -a HERO_TAPS=("540 500" "540 650" "540 350")
declare -a PLAY_TAPS=("540 1255" "540 1150" "540 1350")
MAX_WAIT=${MAX_WAIT:-150}   # max seconds to poll for auto-capture

mkdir -p /tmp/e2e
rm -f /tmp/e2e/*.png /tmp/e2e/*.xml /tmp/e2e/*.txt

adb() { timeout 30 $ADB -s $DEV "$@"; }

shot() { # $1 = filename ; writes md5 to global SHOT_MD5
  local f="/tmp/e2e/$1"
  rm -f "$f"
  timeout 30 $ADB -s $DEV exec-out screencap -p > "$f" 2>/dev/null
  if [ ! -s "$f" ]; then
    # fallback: screencap to device then cat
    timeout 30 $ADB -s $DEV shell screencap -p /sdcard/s.png >/dev/null 2>&1
    timeout 30 $ADB -s $DEV exec-out cat /sdcard/s.png > "$f" 2>/dev/null
  fi
  SHOT_MD5=$(md5sum < "$f" 2>/dev/null | awk '{print $1}')
  echo "$1: $(wc -c < "$f" 2>/dev/null) bytes md5=${SHOT_MD5:-none}"
}

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
  BOOT=$(timeout 10 $ADB -s $DEV shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  if [ "$BOOT" = "1" ]; then echo "BOOTED at ~$((i*10))s"; BOOTED=1; break; fi
  sleep 10
done
if [ "$BOOTED" != "1" ]; then
  echo "BOOT FAILED"; tail -20 /tmp/e2e/emulator.log
  kill $EMU_PID 2>/dev/null; exit 4
fi

echo "### 3. WAKE + STAY AWAKE"
adb shell input keyevent 224 >/dev/null 2>&1     # KEYCODE_WAKEUP
adb shell wm dismiss-keyguard >/dev/null 2>&1
adb shell svc power stayon true >/dev/null 2>&1
adb shell settings put system screen_off_timeout 1800000 >/dev/null 2>&1
sleep 2

echo "### 4. INSTALL APK"
adb install -r "$APK" 2>&1 | tail -1

echo "### 5. CLEAR LOGCAT + LAUNCH"
adb logcat -c 2>/dev/null || true
adb shell am start -n $PKG/.MainActivity 2>&1 | head -1
# wait for the app process to be alive
APP_UP=0
for i in $(seq 1 12); do
  if timeout 10 $ADB -s $DEV shell pidof $PKG >/dev/null 2>&1; then echo "APP_UP at ~${i}s"; APP_UP=1; break; fi
  sleep 5
done
[ "$APP_UP" = "1" ] || { echo "APP NEVER STARTED"; kill $EMU_PID 2>/dev/null; exit 4; }
sleep 12

echo "### 6. HOME SCREENSHOT"
shot 1_home.png
MD5_HOME="$SHOT_MD5"

echo "### 7. TAP HERO (with verification + retry)"
TAPPED=0
for t in "${HERO_TAPS[@]}"; do
  set -- $t
  echo "-- tap hero $1,$2"
  adb shell input tap "$1" "$2"
  sleep 8
  shot 2_detail.png
  if [ -n "$SHOT_MD5" ] && [ "$SHOT_MD5" != "$MD5_HOME" ] && [ -n "$MD5_HOME" ]; then
    echo "NAVIGATION CONFIRMED (detail differs from home)"
    TAPPED=1; break
  fi
  echo "screen unchanged — retrying with next coordinate"
done
if [ "$TAPPED" != "1" ]; then
  echo "COULD NOT NAVIGATE TO DETAIL"
  kill $EMU_PID 2>/dev/null; exit 3
fi

echo "### 8. TAP PLAY (with verification + retry)"
PLAYED=0
for t in "${PLAY_TAPS[@]}"; do
  set -- $t
  echo "-- tap play $1,$2"
  adb shell input tap "$1" "$2"
  sleep 6
  # the player screen ALWAYS logs FILMKU_EXTRACT_SUMMARY on load
  if timeout 20 $ADB -s $DEV logcat -d 2>/dev/null | grep -q 'FILMKU_EXTRACT_SUMMARY'; then
    echo "PLAYER SCREEN REACHED (FILMKU_EXTRACT_SUMMARY logged)"
    PLAYED=1; break
  fi
  echo "no player logs yet — retrying with next coordinate"
done
if [ "$PLAYED" != "1" ]; then
  echo "COULD NOT REACH PLAYER SCREEN"
  kill $EMU_PID 2>/dev/null; exit 3
fi
shot 3_player_start.png

echo "### 9. POLL AUTO-CAPTURE (up to ${MAX_WAIT}s, early-exit)"
RESULT="unknown"
for i in $(seq 1 $((MAX_WAIT / 10))); do
  sleep 10
  LOGS=$(timeout 20 $ADB -s $DEV logcat -d 2>/dev/null | grep -E 'FILMKU_')
  if echo "$LOGS" | grep -q 'FILMKU_AUTOCAPTURE_CAPTURED\|FILMKU_AUTOCAPTURE_OK'; then
    RESULT="captured"; echo ">> CAPTURED at ~$((i*10))s"; break
  fi
  if echo "$LOGS" | grep -q 'FILMKU_AUTOCAPTURE_TIMEOUT all providers exhausted'; then
    RESULT="exhausted"; echo ">> ALL PROVIDERS EXHAUSTED at ~$((i*10))s"; break
  fi
  if echo "$LOGS" | grep -q 'FILMKU_MPV_OPEN'; then
    RESULT="mpv"; echo ">> MPV PLAYER OPEN at ~$((i*10))s"; break
  fi
done
shot 4_player_end.png

echo "### 10. FULL FILMKU LOGCAT EVIDENCE"
adb logcat -d 2>/dev/null | grep -E 'FILMKU_' > /tmp/e2e/logcat.txt
echo "logcat lines: $(wc -l < /tmp/e2e/logcat.txt)"
cat /tmp/e2e/logcat.txt

echo "### 11. SUMMARY"
echo "RESULT=$RESULT"

echo "### 12. TEARDOWN"
kill $EMU_PID 2>/dev/null
sleep 2
pkill -f 'emulator.*filmku' 2>/dev/null
echo "DONE"

case "$RESULT" in
  captured|mpv) exit 0 ;;
  exhausted)    exit 2 ;;
  *)            exit 3 ;;
esac
