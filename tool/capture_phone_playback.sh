#!/usr/bin/env bash
# Interactive evidence capture from the phone.
#   - clears logcat, launches FilmKU
#   - polls for playback evidence (FILMKU_MPV_PLAYING / WEBVIEW_OPEN /
#     EXTRACT_SUMMARY) up to WINDOW seconds
#   - the moment playback evidence appears: SCREENSHOT the player + dump logcat
#   - after the window: dump full FILMKU_ evidence
# Run this, then ask the user to open a movie on their phone immediately.
export ANDROID_HOME=/opt/android-sdk
export PATH=/opt/android-sdk/platform-tools:$PATH
ADB=adb
SERIAL=${1:-mrdm5povbql7guob}
PKG=com.filmku.filmku
WINDOW=${WINDOW:-180}

echo "### CLEAR LOGCAT + LAUNCH APP"
timeout 10 $ADB -s "$SERIAL" logcat -c 2>/dev/null || true
timeout 10 $ADB -s "$SERIAL" shell am start -n $PKG/.MainActivity 2>&1 | head -1

echo "### POLL FOR PLAYBACK EVIDENCE (up to ${WINDOW}s) — PUTAR FILM SEKARANG"
SHOT=0
for i in $(seq 1 $((WINDOW / 5))); do
  sleep 5
  LOGS=$(timeout 15 $ADB -s "$SERIAL" logcat -d 2>/dev/null | grep -E 'FILMKU_')
  if [ "$SHOT" = "0" ]; then
    if echo "$LOGS" | grep -qE 'FILMKU_MPV_PLAYING|FILMKU_MPV_OPENED|FILMKU_WEBVIEW_OPEN|FILMKU_EXTRACT_SUMMARY|FILMKU_MPV_OPEN '; then
      echo ">> PLAYER EVIDENCE at ~$((i*5))s — SCREENSHOT"
      timeout 15 $ADB -s "$SERIAL" exec-out screencap -p > /tmp/phone_player.png 2>/dev/null
      echo "player screenshot: $(wc -c < /tmp/phone_player.png 2>/dev/null) bytes"
      SHOT=1
    fi
  fi
  if echo "$LOGS" | grep -q 'FILMKU_MPV_PLAYING'; then
    echo ">> MPV PLAYING at ~$((i*5))s — stop waiting"
    sleep 8
    break
  fi
done

echo
echo "### FULL FILMKU_ EVIDENCE"
timeout 30 $ADB -s "$SERIAL" logcat -d 2>/dev/null | grep -E 'FILMKU_' | tail -120
echo
echo "### SCREENSHOTS"
ls -la /tmp/phone_player.png 2>/dev/null || echo 'no player screenshot taken'
