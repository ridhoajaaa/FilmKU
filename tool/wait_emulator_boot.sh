#!/bin/bash
# wait_emulator_boot.sh — wait for emulator boot and report status
export ADB=/opt/android-sdk/platform-tools/adb

echo "=== WAIT EMULATOR BOOT (up to 300s) ==="
BOOTED=0
for i in $(seq 1 30); do
  BOOT=$($ADB -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  if [ "$BOOT" = "1" ]; then
    echo "EMULATOR_BOOTED after ~$((i*10))s"
    BOOTED=1
    break
  fi
  sleep 10
done
if [ "$BOOTED" = "0" ]; then
  echo "EMULATOR_NOT_BOOTED (timeout)"
fi

echo
echo "=== ADB DEVICES ==="
$ADB devices

echo
echo "=== EMULATOR API LEVEL ==="
$ADB -s emulator-5554 shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r'

echo
echo "=== EMULATOR PROC ==="
ps aux | grep 'emulator.*filmku' | grep -v grep | awk '{print "PID", $2}' | head -2

echo
echo "=== EMULATOR LOG TAIL ==="
tail -6 /tmp/emulator3.log 2>/dev/null
