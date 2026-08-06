#!/usr/bin/env bash
# Test screencap orientation behavior: capture NOW (should be portrait —
# WhatsApp) and check output dimensions. Also re-check app manifest for any
# screenOrientation constraint.
export ANDROID_HOME=/opt/android-sdk
export PATH=/opt/android-sdk/platform-tools:$PATH
ADB=adb
SERIAL=${1:-mrdm5povbql7guob}

echo '=== display now ==='
timeout 10 $ADB -s "$SERIAL" shell dumpsys display 2>/dev/null | grep -iE 'mCurrentOrientation|DeviceInfo\{' | head -3

echo
echo '=== screencap now ==='
timeout 15 $ADB -s "$SERIAL" exec-out screencap -p > /tmp/now.png 2>/dev/null
echo "bytes: $(wc -c < /tmp/now.png 2>/dev/null)"
python3 - <<'EOF'
from PIL import Image
img = Image.open('/tmp/now.png')
print(f'screenshot dimensions: {img.size[0]}x{img.size[1]}')
EOF

echo
echo '=== AndroidManifest orientation ==='
find /home/ridhoajaaa/DataD/FreeBuff/FilmKU/android -name 'AndroidManifest.xml' | while read f; do
  echo "--- $f"
  grep -iE 'screenOrientation|MainActivity|android:name="\.MainActivity"' "$f" | head -6
done

echo
echo '=== MIUI auto-rotate setting ==='
timeout 10 $ADB -s "$SERIAL" shell settings get system accelerometer_rotation 2>/dev/null
timeout 10 $ADB -s "$SERIAL" shell settings get system user_rotation 2>/dev/null
