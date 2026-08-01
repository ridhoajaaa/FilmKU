#!/bin/bash
# Analisis lanjutan DeepCine APK: assets, endpoint API, sumber stream.
cd /tmp/deepcine

echo '=== 1. Isi assets/ ==='
ls -la assets/ 2>/dev/null | head -30

echo
echo '=== 2. File assets non-gambar ==='
find assets -type f 2>/dev/null | grep -viE '\.(png|jpg|jpeg|webp|gif|xml)$' | head -20

echo
echo '=== 3. Endpoint API app (pola api./backend/server/app.) ==='
strings -n 6 /tmp/all_dex.bin 2>/dev/null | grep -o -E '(https?://)?(api|backend|server|app|cms|cdn|v[0-9])\.[a-z0-9.-]+\.(com|net|io|app|xyz|cc|tv|me|su)' | sort -u | head -30

echo
echo '=== 4. URL unik domain yang bukan iklan (frek rendah, tapi mencurigakan) ==='
strings -n 8 /tmp/all_dex.bin 2>/dev/null | grep -o -E 'https?://[a-zA-Z0-9.-]+' | sort | uniq -c | sort -rn | grep -viE 'google|github|w3\.org|whatwg|schema|doubleclick|applovin|unity|adjust|mossturbo|inner-active|facebook|googlesyndication|safedk|pangle|inmobi|mnbvcxzas|tiktokpangle|example' | head -30

echo
echo '=== 5. String URL lengkap berisi path (stream/movie/api) ==='
strings -n 10 /tmp/all_dex.bin 2>/dev/null | grep -o -E 'https?://[^ ]+' | grep -iE '(stream|movie|watch|hls|m3u8|play|embed|media|video)' | grep -viE 'google|github|w3\.org|schema|doubleclick|applovin|unity|adjust|mossturbo|inner-active|facebook|syndication|safedk|pangle|inmobi|tiktokpangle' | sort -u | head -25
