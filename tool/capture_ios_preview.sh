#!/usr/bin/env bash
# Capture the iOS liquid-glass UI from a LIVE Linux run (headless via Xvfb)
# and verify the glass capsule renders (aqua accent band in the bottom half).
#
# Prereqs: Xvfb, ImageMagick `import`, and a debug build made WITH the flag:
#   flutter run -d linux --dart-define=FILMKU_FORCE_IOS_UI=true
# (that bakes the flag into build/linux/x64/debug/bundle/filmku).
#
# Usage: bash tool/capture_ios_preview.sh
set -u
cd "$(dirname "$0")/.." || exit 1
BIN=build/linux/x64/debug/bundle/filmku
OUT=/tmp/filmku_ios_xvfb.png
LOG=/tmp/filmku_xvfb_run.log

if [ ! -x "$BIN" ]; then
  echo "NO_BINARY: build first with:"
  echo "  flutter run -d linux --dart-define=FILMKU_FORCE_IOS_UI=true"
  echo "(or: flutter build linux --debug --dart-define=FILMKU_FORCE_IOS_UI=true)"
  exit 2
fi

# Clean up any previous instance.
pkill -f 'bundle/filmku' 2>/dev/null
pkill -f 'Xvfb :99' 2>/dev/null
sleep 1

Xvfb :99 -screen 0 1280x800x24 > /tmp/xvfb.log 2>&1 &
XVFB_PID=$!
sleep 3

DISPLAY=:99 GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 "$BIN" > "$LOG" 2>&1 &
APP_PID=$!
echo "app pid: $APP_PID  (waiting 18s for first frames)"
sleep 18

echo '=== APP LOG (tail) ==='
tail -4 "$LOG"

echo '=== CAPTURE (import -window root on :99) ==='
if DISPLAY=:99 import -window root "$OUT" 2>/tmp/import_err.log; then
  ls -la "$OUT"
  python3 tool/check_live_ios_screenshot.py "$OUT"
else
  echo "IMPORT_FAILED: $(cat /tmp/import_err.log)"
fi

kill "$APP_PID" 2>/dev/null
kill "$XVFB_PID" 2>/dev/null
pkill -f 'bundle/filmku' 2>/dev/null
pkill -f 'Xvfb :99' 2>/dev/null
echo DONE
