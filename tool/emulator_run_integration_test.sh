#!/bin/bash
# emulator_run_integration_test.sh — ONE-SHOT integration test on the emulator.
#
# Strategy (hardened against host RAM ~7.6GB + full swap, which OOM-killed the
# emulator during `flutter drive`'s VM-service session):
#   1. BUILD the test APK first (no emulator running → RAM/Gradle uncontended)
#      with `--target=integration_test/auto_capture_test.dart`,
#   2. kill Gradle daemons to free host RAM,
#   3. boot the emulator small (1024MB, 540x960 skin, 2 cores — minimal
#      host/guest footprint so the WebView survives),
#   4. INSTALL the APK and LAUNCH the test activity directly via
#      `am start` (NO flutter drive, NO VM service, NO driver connection —
#      the test's debugPrint E2E_ lines land straight in logcat),
#   5. poll logcat for E2E_ evidence,
#   6. teardown.
export ANDROID_HOME=/opt/android-sdk
export PATH=/opt/android-sdk/platform-tools:/home/ridhoajaaa/flutter/bin:$PATH
ADB=/opt/android-sdk/platform-tools/adb
EMU=/opt/android-sdk/emulator/emulator
PROJ=/home/ridhoajaaa/DataD/FreeBuff/FilmKU
APK=$PROJ/build/app/outputs/flutter-apk/app-debug.apk
DEV=emulator-5554
PKG=com.filmku.filmku
POLL_MAX=${POLL_MAX:-210}   # max seconds to poll logcat for E2E evidence

mkdir -p /tmp/e2e
rm -f /tmp/e2e/*.txt /tmp/e2e/*.log

echo "### 0. BUILD TEST APK (no emulator running yet)"
cd "$PROJ" || exit 4
timeout 600 flutter build apk --debug \
  --target=integration_test/auto_capture_test.dart 2>&1 | tail -5
BUILD_EXIT=${PIPESTATUS[0]}
echo "BUILD_EXIT=$BUILD_EXIT"
ls -la "$APK" 2>/dev/null || { echo "NO_APK_AFTER_BUILD"; exit 4; }

echo "### 0.5 FREE HOST MEMORY (gradle + dart + java + drop caches)"
pkill -f 'GradleDaemon' 2>/dev/null
pkill -f 'gradle.*daemon' 2>/dev/null
pkill -f 'dart.*flutter_tools' 2>/dev/null
pkill -f 'kotlin.*daemon' 2>/dev/null
sleep 3
sync 2>/dev/null
# drop page cache to reclaim reclaimable RAM (works if not root via /proc? may fail silently)
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
echo "free before emulator: $(free -m | awk 'NR==2{print $4}') MB (avail: $(free -m | awk 'NR==2{print $7}') MB)"

echo "### 1. START EMULATOR (1024MB, 540x960, 2 cores)"
pkill -f 'emulator.*filmku' 2>/dev/null
pkill -f 'qemu.*filmku' 2>/dev/null
sleep 2
# 1536MB/720x1280 is the PROVEN config: it booted AND ran the test (logged
# FILMKU_AUTOCAPTURE_OPEN + USERSCRIPT_ADDED). 1024MB got the app killed by
# the guest system before evidence. Keep the proven config.
$EMU -avd filmku -no-window -no-audio -no-boot-anim \
  -gpu swiftshader_indirect -no-snapshot -no-metrics \
  -memory 1536 -cores 4 -skin 720x1280 \
  > /tmp/e2e/emulator.log 2>&1 &
EMU_PID=$!
echo "EMU_PID=$EMU_PID"

echo "### 2. WAIT BOOT (up to 300s)"
BOOTED=0
for i in $(seq 1 30); do
  BOOT=$(timeout 8 $ADB -s $DEV shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  if [ "$BOOT" = "1" ]; then echo "BOOTED at ~$((i*10))s"; BOOTED=1; break; fi
  sleep 10
done
if [ "$BOOTED" != "1" ]; then
  echo "BOOT FAILED"; tail -20 /tmp/e2e/emulator.log
  kill $EMU_PID 2>/dev/null; exit 4
fi

echo "### 3. WAKE + INSTALL"
timeout 8 $ADB -s $DEV shell input keyevent 224 >/dev/null 2>&1
timeout 8 $ADB -s $DEV shell wm dismiss-keyguard >/dev/null 2>&1
timeout 8 $ADB -s $DEV shell svc power stayon true >/dev/null 2>&1
timeout 120 $ADB -s $DEV install -r "$APK" 2>&1 | tail -1
timeout 8 $ADB -s $DEV logcat -c 2>/dev/null || true

echo "### 4. LAUNCH TEST ACTIVITY DIRECTLY (no flutter drive)"
timeout 8 $ADB -s $DEV shell am start -n $PKG/.MainActivity 2>&1 | head -1

echo "### 5. POLL LOGCAT FOR E2E EVIDENCE (up to ${POLL_MAX}s)"
RESULT="unknown"
for i in $(seq 1 $((POLL_MAX / 10))); do
  sleep 10
  LOGS=$(timeout 20 $ADB -s $DEV logcat -d 2>/dev/null | grep -E 'E2E_|FILMKU_')
  if echo "$LOGS" | grep -q 'E2E_ALL_RESULTS'; then
    RESULT="finished"; echo ">> TEST FINISHED at ~$((i*10))s"; break
  fi
  if echo "$LOGS" | grep -q 'E2E_CAPTURED'; then
    RESULT="captured"; echo ">> CAPTURED at ~$((i*10))s"; break
  fi
  # app died? (crash / OOM) — only after a 30s grace window so a slow
  # cold start on the SwiftShader emulator isn't misread as a crash.
  if [ $((i*10)) -ge 30 ]; then
    if ! timeout 8 $ADB -s $DEV shell pidof $PKG >/dev/null 2>&1; then
      echo ">> APP PROCESS GONE at ~$((i*10))s"
      RESULT="app_died"; break
    fi
  fi
done

echo "### 6. FULL EVIDENCE"
timeout 30 $ADB -s $DEV logcat -d 2>/dev/null | grep -E 'E2E_|FILMKU_' > /tmp/e2e/logcat.txt
echo "logcat E2E/FILMKU lines: $(wc -l < /tmp/e2e/logcat.txt)"
cat /tmp/e2e/logcat.txt
echo "--- app-side crash? ---"
timeout 30 $ADB -s $DEV logcat -d 2>/dev/null | grep -iE 'FATAL|AndroidRuntime' | grep -i filmku | tail -5 || true

echo "### 7. VERDICT"
if grep -q 'E2E_CAPTURED' /tmp/e2e/logcat.txt; then
  echo "VERDICT=CAPTURED"; RESULT_EXIT=0
elif grep -q 'E2E_ALL_RESULTS' /tmp/e2e/logcat.txt; then
  echo "VERDICT=NO_CAPTURE"; RESULT_EXIT=2
else
  echo "VERDICT=NO_EVIDENCE (result=$RESULT)"; RESULT_EXIT=3
fi

echo "### 8. TEARDOWN"
kill $EMU_PID 2>/dev/null
sleep 2
pkill -f 'emulator.*filmku' 2>/dev/null
echo "DONE (build=$BUILD_EXIT result=$RESULT verdict=$RESULT_EXIT)"
exit $RESULT_EXIT
