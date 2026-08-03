#!/usr/bin/env bash
set -u
DEX=/tmp/all_dex.bin

echo "=== A. tv_secret context ==="
strings "$DEX" | grep -iE 'tv_secret' | sort -u | head -10

echo
echo "=== B. around /api/vod (template) ==="
strings "$DEX" | grep -iE '/api/vod' | sort -u | head -10

echo
echo "=== C. app_ver / appkey full strings ==="
strings "$DEX" | grep -oE '[a-zA-Z0-9_=&?%.{}:/.-]{8,140}(app_ver|appkey|app_key|AppKey)[a-zA-Z0-9_=&?%.{}:/.-]{0,60}' | sort -u | head -20
strings "$DEX" | grep -oE '(app_ver|appkey|app_key|AppKey)=[a-zA-Z0-9_.-]{3,40}' | sort -u | head -20

echo
echo "=== D. hex secrets near md5/secret strings ==="
strings "$DEX" | grep -oE '"[a-f0-9]{16,64}"' | sort -u | head -20

echo
echo "=== E. PROBE /api/vod endpoints ==="
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
BASE="https://velvetreel.7nkznc.com"
for path in "/api/vod/info" "/api/vod/info_new"; do
  for q in "" "?tmdb=1368337" "?id=1368337" "?movie_id=1368337" "?appkey=1"; do
    code=$(curl -s -o /tmp/vr_r.json -w '%{http_code}' --max-time 10 -A "$UA" "$BASE$path$q" 2>/dev/null)
    body=$(head -c 160 /tmp/vr_r.json 2>/dev/null | tr -d '\n')
    echo "$code  $path$q  ->  $body"
  done
done
