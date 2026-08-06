#!/usr/bin/env bash
# Reproduce the mpv player layout ON THE PHONE using the deterministic
# vidnest integration test (extracts 634649 → vnest → mpv, real app code).
# Captures: screenshot + display rotation + app window size at PLAYING.
export ANDROID_HOME=/opt/android-sdk
export PATH=/opt/android-sdk/platform-tools:/home/ridhoajaaa/flutter/bin:$PATH
ADB=adb
SERIAL=${1:-mrdm5povbql7guob}
PKG=com.filmku.filmku
PROJ=/home/ridhoajaaa/DataD/FreeBuff/FilmKU
APK=$PROJ/build/app/outputs/flutter-apk/app-debug.apk

echo "### 1. BUILD arm64 debug APK (vidnest test target)"
cd "$PROJ" || exit 1
timeout 600 flutter build apk --debug \
  --target-platform=android-arm64 \
  --target=integration_test/vidnest_native_test.dart 2>&1 | tail -3
ls -la "$APK" 2>/dev/null || { echo 'NO APK'; exit 1; }

echo
echo "### 2. INSTALL ON PHONE"
timeout 300 $ADB -s "$SERIAL" install -r -d "$APK" 2>&1 | tail -2

echo
echo "### 3. CLEAR LOGCAT + LAUNCH TEST"
timeout 10 $ADB -s "$SERIAL" logcat -c 2>/dev/null || true
timeout 10 $ADB -s "$SERIAL" shell am start -n $PKG/.MainActivity 2>&1 | head -1

echo
echo "### 4. WAIT FOR PLAYBACK + CAPTURE"
SHOT=0
for i in $(seq 1 44); do
  sleep 5
  if [ "$SHOT" = "0" ]; then
    if timeout 15 $ADB -s "$SERIAL" logcat -d 2>/dev/null | grep -q 'FILMKU_MPV_PLAYING'; then
      sleep 4
      echo ">> PLAYBACK EVIDENCE at ~$((i*5))s — capturing"
      timeout 15 $ADB -s "$SERIAL" exec-out screencap -p > /tmp/phone_repro_player.png 2>/dev/null
      echo "screenshot: $(wc -c < /tmp/phone_repro_player.png 2>/dev/null) bytes"
      echo '--- display rotation ---'
      timeout 10 $ADB -s "$SERIAL" shell dumpsys display 2>/dev/null | grep -i 'mCurrentOrientation' | head -1
      echo '--- window size ---'
      timeout 10 $ADB -s "$SERIAL" shell dumpsys window displays 2>/dev/null | grep -iE 'cur=|init=' | head -2
      SHOT=1
    fi
  fi
  if timeout 15 $ADB -s "$SERIAL" logcat -d 2>/dev/null | grep -q 'E2E_ALL_RESULTS'; then
    echo ">> TEST FINISHED at ~$((i*5))s"
    break
  fi
done

echo
echo "### 5. EVIDENCE (mpv + subs lines)"
timeout 30 $ADB -s "$SERIAL" logcat -d 2>/dev/null | grep -E 'FILMKU_MPV_|FILMKU_SUBS|E2E_' | tail -40
