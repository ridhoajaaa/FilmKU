#!/bin/bash
# Pulls the newest hardware-button screenshot from the phone's gallery.
# The user's own screenshot (Power+VolumeDown) captures the REAL player
# screen — adb screencap/screenrecord can't see the mpv SurfaceView on MIUI.
export PATH=/opt/android-sdk/platform-tools:$PATH
S=${1:-mrdm5povbql7guob}
mkdir -p /tmp/player_probe

F=$(adb -s "$S" shell ls -t /sdcard/DCIM/Screenshots/ 2>/dev/null | head -1)
if [ -z "$F" ]; then
  F=$(adb -s "$S" shell ls -t /sdcard/Pictures/Screenshots/ 2>/dev/null | head -1)
fi
echo "latest gallery screenshot: $F"
if [ -z "$F" ]; then
  echo "none found"
  exit 1
fi
adb -s "$S" pull "/sdcard/DCIM/Screenshots/$F" /tmp/player_probe/hw_shot.png 2>/dev/null \
  || adb -s "$S" pull "/sdcard/Pictures/Screenshots/$F" /tmp/player_probe/hw_shot.png 2>/dev/null
python3 -c "from PIL import Image; im=Image.open('/tmp/player_probe/hw_shot.png'); print('dims:', im.size)"
