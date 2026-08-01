#!/bin/bash
cd /tmp && rm -rf apk_verify_mpv && mkdir apk_verify_mpv && cd apk_verify_mpv
unzip -o -q /home/ridhoajaaa/DataD/FreeBuff/FilmKU/build/app/outputs/flutter-apk/app-release.apk lib/arm64-v8a/libapp.so
echo '=== MPV/MEDIA_KIT STRINGS IN APK ==='
for s in 'FILMKU_MPV_OPEN' 'FILMKU_MPV_ERROR' 'FILMKU_MPV_FAILED' 'FILMKU_MPV_OPENED' 'mpv-player' 'media_kit' 'Play natively' 'iklan diblokir'; do
  echo -n "$s: "
  strings lib/arm64-v8a/libapp.so | grep -c "$s"
done
echo '=== libmpv native libs in APK ==='
unzip -l /home/ridhoajaaa/DataD/FreeBuff/FilmKU/build/app/outputs/flutter-apk/app-release.apk 2>/dev/null | grep -iE 'libmpv|libmedia_kit|ffmpeg' | head -8
echo '=== SIGNATURE ==='
/opt/android-sdk/build-tools/36.0.0/apksigner verify --print-certs /home/ridhoajaaa/DataD/FreeBuff/FilmKU/build/app/outputs/flutter-apk/app-release.apk 2>/dev/null | grep -i 'DN:'
echo '=== LAST UPDATE ON DEVICE ==='
adb shell dumpsys package com.filmku.filmku 2>/dev/null | grep -i lastUpdateTime
