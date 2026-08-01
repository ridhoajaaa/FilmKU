#!/bin/bash
# Analisis lanjutan DeepCine: network security config, res/raw, API konten, pola vod.
cd /tmp/deepcine

echo '=== 1. network_security_config.xml ==='
unzip -o -q '/home/ridhoajaaa/Unduhan/DeepCine_4.0.0-Rev1@armeabi-v7a+arm64-v8a-opt.apk' 'res/xml/network_security_config.xml' -d /tmp/deepcine/ns 2>/dev/null
cat /tmp/deepcine/ns/res/xml/network_security_config.xml 2>/dev/null

echo
echo '=== 2. res/raw files ==='
unzip -l '/home/ridhoajaaa/Unduhan/DeepCine_4.0.0-Rev1@armeabi-v7a+arm64-v8a-opt.apk' 2>/dev/null | grep -iE 'res/raw' | head -15

echo
echo '=== 3. Semua host m3u8 vod di dex (pola /vod/ atau index*.m3u8) ==='
strings -n 8 /tmp/all_dex.bin 2>/dev/null | grep -o -E '[a-z0-9.-]+/[a-z0-9]+/[0-9]+/[0-9/]+[a-z0-9]*/(index[0-9]*)?\.?m3u8[^ ]*' | head -10
strings -n 8 /tmp/all_dex.bin 2>/dev/null | grep -o -E 'https?://[^ ]+\.m3u8[^ ]*' | sort -u | head -10

echo
echo '=== 4. Domain non-iklan unik (semua) ==='
strings -n 8 /tmp/all_dex.bin 2>/dev/null | grep -o -E 'https?://[a-zA-Z0-9.-]+' | sed 's|https\?://||' | sort -u | grep -viE 'google|github|w3\.org|whatwg|schema|doubleclick|applovin|unity|adjust|mossturbo|inner-active|facebook|syndication|safedk|pangle|inmobi|tiktokpangle|apache|jetbrains|apple|exoplayer|youtube|dashif|aomedia|dg10|xmlpull|purl|ns\.adobe|developer|goo\.gle|youtrack|g\.co|example|whatwg|127\.0|vungle|hookspf|funmora|adaether|maxesads|mythad|supersonic|unioneeu|mediation|gg/mads' | head -30

echo
echo '=== 5. Cari endpoint path umum (vod/movie/list/detail/get) ==='
strings -n 6 /tmp/all_dex.bin 2>/dev/null | grep -o -E '"/[a-z0-9_/-]{3,50}"' | grep -iE 'vod|movie|film|video|detail|list|search|play|stream|source|api' | sort -u | head -25
