#!/bin/bash
# Waits until the FilmKU PLAYER is actually open (logcat shows
# FILMKU_MPV_OPENED or FILMKU_WEBVIEW_OPEN) OR the app is foreground, then
# captures screenshots + rotation. The player screenshot is what the
# "controls in the middle" investigation needs.
#
# Usage: bash tool/wait_player_capture.sh [serial] [wait_seconds]
export PATH=/opt/android-sdk/platform-tools:$PATH
S=${1:-mrdm5povbql7guob}
WAIT=${2:-240}
mkdir -p /tmp/player_probe

echo "waiting up to ${WAIT}s for PLAYER evidence..."
FOUND=0
for i in $(seq 1 $((WAIT / 3))); do
  LOGS=$(adb -s "$S" logcat -d -t 300 2>/dev/null | grep -E 'FILMKU_MPV_OPENED|FILMKU_WEBVIEW_OPEN')
  if [ -n "$LOGS" ]; then
    echo "PLAYER EVIDENCE at ~$((i * 3))s:"
    echo "$LOGS" | tail -3
    FOUND=1
    break
  fi
  sleep 3
done
if [ "$FOUND" = "0" ]; then
  echo "TIMEOUT: no player evidence in logcat. App state:"
  adb -s "$S" shell dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity' | head -1
  echo "latest FILMKU_ logs:"
  adb -s "$S" logcat -d -t 400 2>/dev/null | grep -E 'FILMKU_' | tail -6
  exit 5
fi

sleep 3
for n in 1 2 3; do
  adb -s "$S" exec-out screencap -p > "/tmp/player_probe/player$n.png" 2>/dev/null
  echo "player$n: $(wc -c < /tmp/player_probe/player$n.png 2>/dev/null) bytes"
  sleep 2
done
echo "=== rotation ==="
adb -s "$S" shell dumpsys input 2>/dev/null | grep SurfaceOrientation | head -1
echo "=== window ==="
adb -s "$S" shell dumpsys window displays 2>/dev/null | grep -E 'cur=|init=' | head -2
echo DONE
