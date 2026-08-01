#!/bin/bash
# check_e2e_artifacts.sh — inspect what the timed-out run left behind
export ADB=/opt/android-sdk/platform-tools/adb

echo "=== ARTIFACTS IN /tmp/e2e ==="
ls -la /tmp/e2e/ 2>/dev/null || echo "no /tmp/e2e"

echo
echo "=== LOGCAT EVIDENCE (if any) ==="
if [ -f /tmp/e2e/logcat.txt ]; then
  wc -l /tmp/e2e/logcat.txt
  head -60 /tmp/e2e/logcat.txt
else
  echo "no logcat.txt"
fi

echo
echo "=== EMULATOR LOG TAIL ==="
tail -10 /tmp/e2e/emulator.log 2>/dev/null || echo "no emulator.log"

echo
echo "=== SCREENSHOTS ==="
for f in /tmp/e2e/1_home.png /tmp/e2e/2_detail.png /tmp/e2e/3_player_start.png /tmp/e2e/4_player_after.png /tmp/e2e/5_final.png; do
  if [ -f "$f" ]; then
    echo "$f: $(wc -c < "$f") bytes"
  else
    echo "$f: MISSING"
  fi
done

echo
echo "=== EMULATOR STILL RUNNING? ==="
ps aux | grep 'emulator.*filmku' | grep -v grep | awk '{print "PID", $2}' | head -3 || echo "NOT_RUNNING"

echo
echo "=== ADB DEVICES ==="
$ADB devices
