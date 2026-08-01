#!/bin/bash
# DeepCine probe 3: CDN vod hidup? API konten yang mengembalikan URL m3u8?
cd /tmp/deepcine
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'

echo '=== 1. CDN sdgc.e6r4r1.com hidup? (HEAD + GET) ==='
curl -s -L --max-time 12 -A "$UA" -o /tmp/dc_m3u8.txt -w 'HTTP=%{http_code} size=%{size_download} type=%{content_type}\n' \
  'http://sdgc.e6r4r1.com/vod/1/2025/03/20/d6a8f2df6239/index5.m3u8?wsSecret=68a60627f7e0ae99b3d7d9dea55043b3&wsTime=6971e822' 2>&1
echo '--- isi m3u8 (jika ada) ---'
head -c 500 /tmp/dc_m3u8.txt 2>/dev/null
echo

echo
echo '=== 2. Pola wsSecret/wsTime di semua dex (backend signature scheme) ==='
strings -n 6 /tmp/all_dex.bin 2>/dev/null | grep -iE 'wsSecret|wsTime|wsKey|ws_sign|v_sign|sign=' | sort -u | head -10

echo
echo '=== 3. Cari string base64 panjang / URL builder di dex ==='
strings -n 10 /tmp/all_dex.bin 2>/dev/null | grep -E '^[A-Za-z0-9+/]{40,}={0,2}$' | head -8

echo
echo '=== 4. API konten potensial: funmora / hookspf / adaether / maxesads ==='
for d in api.funmora.com api.hookspf.com api.adaether.com api.maxesads.com; do
  echo "--- $d ---"
  curl -s --max-time 8 -A "$UA" -o /tmp/dc_api.txt -w 'HTTP=%{http_code} size=%{size_download}\n' "https://$d/" 2>&1
  head -c 200 /tmp/dc_api.txt 2>/dev/null | tr -d '\n' | head -c 200
  echo
done

echo
echo '=== 5. dg10.tv (muncul di dex) ==='
curl -s -L --max-time 8 -A "$UA" -o /tmp/dc_dg.txt -w 'HTTP=%{http_code} size=%{size_download}\n' 'http://dg10.tv/' 2>&1
head -c 200 /tmp/dc_dg.txt 2>/dev/null | tr -d '\n' | head -c 200
echo
