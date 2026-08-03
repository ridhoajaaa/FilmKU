#!/usr/bin/env bash
# Audit DeepCine APK (friend's streaming app) — find HOW it streams movies
# so we can adopt the same working approach in FilmKU.
set -u
APK="/home/ridhoajaaa/Unduhan/DeepCine_4.0.0-Rev1@armeabi-v7a+arm64-v8a-opt.apk"
OUT=/tmp/deepcine
rm -rf "$OUT" && mkdir -p "$OUT"

echo "=== 0. APK meta ==="
ls -la "$APK"
file "$APK"

echo
echo "=== 1. EXTRACT ==="
cd "$OUT"
unzip -o -q "$APK"
echo "top-level:"; ls "$OUT" | head -30
echo "dex files:"; ls -la "$OUT"/*.dex 2>/dev/null | awk '{print $5, $9}'

echo
echo "=== 2. NATIVE LIBS (player hints) ==="
find "$OUT/lib" -type f 2>/dev/null | head -20
echo "--- lib names ---"
find "$OUT/lib" -type f -name '*.so' 2>/dev/null | sed 's/.*lib\///' | sort -u | head -30

echo
echo "=== 3. ASSETS ==="
ls -la "$OUT/assets" 2>/dev/null | head -30

echo
echo "=== 4. ALL DEX CONCATENATED ==="
cat "$OUT"/classes*.dex > /tmp/all_dex.bin 2>/dev/null
wc -c /tmp/all_dex.bin

echo
echo "=== 5. PACKAGE NAME (from manifest via strings) ==="
strings /tmp/all_dex.bin | grep -oE 'package="[a-zA-Z0-9_.]+"' | head -3
strings /tmp/all_dex.bin | grep -oE 'L[a-zA-Z0-9_/]+/MainActivity;' | head -3
strings "$OUT/AndroidManifest.xml" 2>/dev/null | grep -oE '[a-zA-Z0-9_.]{8,}\.[a-zA-Z0-9_.]+' | grep -iE 'cine|movie|film|stream' | sort -u | head -10
