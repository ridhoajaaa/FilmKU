#!/bin/bash
# launch_emulator.sh — start Android emulator persistently (survives caller exit)
export ANDROID_HOME=/opt/android-sdk
export PATH=/opt/android-sdk/platform-tools:$PATH

# Kill any previous instance
pkill -f 'qemu.*filmku' 2>/dev/null
pkill -f 'emulator.*filmku' 2>/dev/null
sleep 2

# Fully detach: setsid (new session) + nohup + redirected stdio
setsid nohup /opt/android-sdk/emulator/emulator \
  -avd filmku \
  -no-window -no-audio -no-boot-anim \
  -gpu swiftshader_indirect \
  -no-snapshot \
  -no-metrics \
  > /tmp/emulator3.log 2>&1 < /dev/null &

echo "LAUNCHED_PID=$!"
sleep 8
echo "=== PROC ALIVE? ==="
ps aux | grep 'emulator.*filmku' | grep -v grep | awk '{print "PID", $2}' | head -2 || echo "NOT_ALIVE"
echo "=== LOG HEAD ==="
head -12 /tmp/emulator3.log
