#!/usr/bin/env bash
# Probe DeepCine's backend domains (velvetreel.*, smartbrowser.*, sdgc.*)
set -u
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'

check() {
  local url="$1"
  local code size
  code=$(curl -s -o /tmp/vr_body.html -w '%{http_code}' --max-time 12 -A "$UA" "$url" 2>/dev/null)
  size=$(wc -c < /tmp/vr_body.html 2>/dev/null || echo 0)
  title=$(grep -oiE '<title>[^<]*</title>' /tmp/vr_body.html 2>/dev/null | head -1 | cut -c1-80)
  echo "$code  $size  $url  $title"
}

echo "=== 1. LIVENESS ==="
for d in velvetreel.7nkznc.com velvetreel.b7m6.com smartbrowser.g8w6.com sdgc.e6r4r1.com; do
  for proto in https http; do
    check "$proto://$d/"
  done
done

echo
echo "=== 2. COMMON API PATHS on velvetreel.7nkznc.com ==="
BASE="https://velvetreel.7nkznc.com"
for p in \
  "/" "/api/" "/v1/" "/v2/" "/api/v1/" \
  "/api/movie/155" "/api/movie/1368337" \
  "/movie/1368337" "/movies/1368337" \
  "/api/stream/1368337" "/api/stream?tmdb=1368337" \
  "/api/search?q=test" "/config" "/api/config" \
  "/api/source/1368337" "/api/play/1368337" \
  "/api/v1/movie/1368337" "/v3/media/movie/1368337" \
  "/api/tmdb/1368337" "/api/detail/1368337"; do
  check "$BASE$p"
done

echo
echo "=== 3. SAMPLE BODY (if any JSON) ==="
for p in "/" "/api/" "/api/movie/1368337" "/api/stream/1368337"; do
  echo "--- $BASE$p ---"
  curl -s --max-time 10 -A "$UA" "$BASE$p" 2>/dev/null | head -c 300
  echo
done
