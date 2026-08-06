#!/bin/bash
# Captures per-pid logcat from the FilmKU app into /tmp/phone_v325.log so
# playback evidence (FILMKU_*) survives the phone's aggressive logcat
# rotation (WhatsApp camera spam fills the buffer in minutes).
#
# Usage: bash tool/capture_phone_log.sh   (starts a 10-min background capture)
export PATH=/opt/android-sdk/platform-tools:$PATH
S=${1:-mrdm5povbql7guob}

PID=$(adb -s "$S" shell pidof com.filmku.filmku | tr -d '\r')
if [ -z "$PID" ]; then
  echo "app not running — launch it first"
  adb -s "$S" shell am start -n com.filmku.filmku/.MainActivity >/dev/null 2>&1
  sleep 6
  PID=$(adb -s "$S" shell pidof com.filmku.filmku | tr -d '\r')
fi
echo "app pid: $PID"

adb -s "$S" logcat -c
echo "logcat cleared"

# Background capture: per-pid only (immune to other apps' log spam), 10 min.
nohup bash -c "timeout 600 adb -s $S logcat --pid=$PID -v time > /tmp/phone_v325.log 2>/dev/null" \
  >/dev/null 2>&1 &
echo "capture started -> /tmp/phone_v325.log (auto-stops in 10 min)"
sleep 3
echo "--- first lines ---"
head -3 /tmp/phone_v325.log 2>/dev/null || echo "(empty so far)"
