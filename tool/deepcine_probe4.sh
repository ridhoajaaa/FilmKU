#!/bin/bash
# DeepCine probe 4: native lib strings + template URL vod + host API asli.
cd /tmp/deepcine
echo '=== 1. Ekstrak native libs ==='
unzip -o -q '/home/ridhoajaaa/Unduhan/DeepCine_4.0.0-Rev1@armeabi-v7a+arm64-v8a-opt.apk' 'lib/arm64-v8a/*' -d /tmp/deepcine/native 2>/dev/null
ls -la /tmp/deepcine/native/lib/arm64-v8a/ 2>/dev/null | head -15

echo
echo '=== 2. libpp_hls.so: string URL/API ==='
strings -n 6 /tmp/deepcine/native/lib/arm64-v8a/libpp_hls.so 2>/dev/null | grep -o -E 'https?://[a-zA-Z0-9.-]+' | sort -u | head -20
echo '--- m3u8/vod/wsSecret di libpp_hls.so ---'
strings -n 6 /tmp/deepcine/native/lib/arm64-v8a/libpp_hls.so 2>/dev/null | grep -iE 'm3u8|vod|wsSecret|wsTime|index[0-9]' | sort -u | head -10

echo
echo '=== 3. libsgcore.so + liballiance.so: string API ==='
for lib in libsgcore.so liballiance.so libnms.so; do
  echo "--- $lib ---"
  strings -n 6 /tmp/deepcine/native/lib/arm64-v8a/$lib 2>/dev/null | grep -o -E 'https?://[a-zA-Z0-9.-]+' | sort -u | head -8
done

echo
echo '=== 4. Template URL vod di dex (pola %s/vod atau vod/) ==='
strings -n 6 /tmp/all_dex.bin 2>/dev/null | grep -E 'vod|index%|/index[0-9]?\.m3u8|%s/vod' | grep -viE 'android|schemas' | sort -u | head -15

echo
echo '=== 5. Cari host yang menyusun URL stream (kemungkinan base url) ==='
strings -n 8 /tmp/all_dex.bin 2>/dev/null | grep -iE 'e6r4r1|sdgc|velvetreel|shorttv|deepcine' | sort -u | head -15
