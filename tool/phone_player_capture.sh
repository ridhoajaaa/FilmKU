#!/bin/bash
# Waits until the FilmKU app is the foreground activity on the phone, then
# captures screenshots + display rotation so the REAL player layout can be
# analyzed pixel-by-pixel (the "controls in the middle" investigation).
#
# Usage: bash tool/phone_player_capture.sh [seconds_to_wait]
export PATH=/opt/android-sdk/platform-tools:$PATH
S=${1:-mrdm5povbql7guob}
WAIT=${2:-150}
mkdir -p /tmp/player_probe

echo "waiting up to ${WAIT}s for filmku to be foreground..."
FOUND=0
for i in $(seq 1 $((WAIT / 3))); do
  ACT=$(adb -s "$S" shell dumpsys activity activities 2>/dev/null \
        | grep -E 'mResumedActivity|topResumedActivity' | head -1)
  if echo "$ACT" | grep -q 'com.filmku.filmku'; then
    echo "APP FOREGROUND at ~$((i * 3))s: $ACT"
    FOUND=1
    break
  fi
  sleep 3
done
if [ "$FOUND" = "0" ]; then
  echo "TIMEOUT: app never became foreground (top activity now:)"
  adb -s "$S" shell dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|topResumedActivity' | head -1
  exit 5
fi

# Give the player a moment to render, then capture.
sleep 4
for n in 1 2 3; do
  adb -s "$S" exec-out screencap -p > "/tmp/player_probe/shot$n.png" 2>/dev/null
  echo "shot$n: $(wc -c < /tmp/player_probe/shot$n.png 2>/dev/null) bytes"
  sleep 4
done

echo "=== rotation ==="
adb -s "$S" shell dumpsys input 2>/dev/null | grep SurfaceOrientation | head -1
echo "=== window ==="
adb -s "$S" shell dumpsys window displays 2>/dev/null | grep -E 'cur=|init=' | head -2
echo "=== top activity ==="
adb -s "$S" shell dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|topResumedActivity' | head -1
echo DONE
