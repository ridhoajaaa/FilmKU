#!/bin/bash
# Probe DeepCine /playable API (found in dex) - is there an unauthenticated path to fresh signed m3u8?
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
echo '=== 1. Context of /playable in dex ==='
if [ -f /tmp/all_dex.bin ]; then
  strings -n 4 /tmp/all_dex.bin | grep -E '/playable|playable' | head -20
fi
echo
echo '=== 2. API path candidates around /playable ==='
if [ -f /tmp/all_dex.bin ]; then
  strings -n 6 /tmp/all_dex.bin | grep -iE 'playable|play' | grep -iE 'http|api|/|=' | head -25
fi
echo
echo '=== 3. Liveness of velvetreel backend (GET variants) ==='
for p in '/' '/playable' '/api/playable' '/api/v1/playable' '/play' '/api/play' '/api/vod' '/api/movie' '/api/detail' '/api/home'; do
  code=$(curl -s -o /tmp/pr.json -w '%{http_code}' --max-time 8 -A "$UA" "http://velvetreel.7nkznc.com$p" 2>/dev/null)
  size=$(wc -c < /tmp/pr.json 2>/dev/null || echo 0)
  echo "  GET $p -> HTTP $code ($size bytes) $(head -c 80 /tmp/pr.json 2>/dev/null)"
done
echo
echo '=== 4. POST /api/playable with movie id guesses ==='
for body in '{"movie_id":155}' '{"id":155}' '{"movieId":155}' '{"tmdb_id":155}' '{"imdb":"tt0468569"}' 'id=155' 'movie_id=155'; do
  code=$(curl -s -o /tmp/pr2.json -w '%{http_code}' --max-time 8 -X POST -A "$UA" -H 'Content-Type: application/json' -d "$body" "http://velvetreel.7nkznc.com/api/playable" 2>/dev/null)
  echo "  POST /api/playable $body -> HTTP $code : $(head -c 120 /tmp/pr2.json 2>/dev/null)"
done
echo
echo '=== 5. HTTPS variants + www ==='
for u in 'https://velvetreel.7nkznc.com/api/playable' 'https://www.velvetreel.7nkznc.com/' 'http://www.velvetreel.7nkznc.com/'; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -A "$UA" "$u" 2>/dev/null)
  echo "  $u -> HTTP $code"
done
