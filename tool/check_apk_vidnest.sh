#!/usr/bin/env bash
# 1) Check if the built release APK contains the VidNest native-extraction
#    strings (so we know whether to rebuild).
# 2) List the FILMKU_ log markers used in the lib source.
set -u
APK=/home/ridhoajaaa/DataD/FreeBuff/FilmKU/build/app/outputs/flutter-apk/app-release.apk
echo '=== VidNest / vnest strings in APK libapp.so ==='
cd /tmp && rm -rf apk_str && mkdir apk_str && cd apk_str
unzip -o -q "$APK" lib/arm64-v8a/libapp.so 2>/dev/null
for s in 'vidNestCandidates' 'fetchVidNestSource' 'VidNest' 'decodeVidNestPayload' 'vnest'; do
  echo -n "  $s: "
  strings lib/arm64-v8a/libapp.so 2>/dev/null | grep -c "$s"
done
echo
echo '=== FILMKU_ markers in lib source (with usage) ==='
grep -rn "FILMKU_[A-Z_]*" /home/ridhoajaaa/DataD/FreeBuff/FilmKU/lib --include='*.dart' -o | sed 's/.*://' | sort -u
