#!/usr/bin/env bash
# Test movie-web style backends: TMDB id -> plain m3u8 (server-side scrape).
set -u
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
MID=1368337

probe() {
  local label="$1"; local url="$2"
  local code
  code=$(curl -s -o /tmp/mw_body.json -w '%{http_code}' --max-time 20 -A "$UA" -H 'Accept: application/json' "$url" 2>/dev/null)
  local body
  body=$(head -c 400 /tmp/mw_body.json 2>/dev/null | tr -d '\n')
  echo "== $label =="
  echo "   $code  $url"
  echo "   body: $body"
  echo
}

echo "=== movie-web public backend (v3) ==="
probe "backend.movie-web.app" "https://backend.movie-web.app/v3/media/movie/$MID"
probe "whvx.net proxy" "https://api.whvx.net/v3/media/movie/$MID"
probe "mw-backend.cam" "https://mw-backend.cam/v3/media/movie/$MID"

echo "=== try alternate paths ==="
probe "backend /v2 media" "https://backend.movie-web.app/v2/media/movie/$MID"
probe "backend root" "https://backend.movie-web.app/"

echo "=== extract any playable URL from responses ==="
for f in /tmp/mw_body.json; do
  python3 - << PY
import json, re
try:
    d = json.load(open('/tmp/mw_body.json'))
    def walk(o, path=''):
        if isinstance(o, dict):
            for k, v in o.items():
                walk(v, path + '.' + k)
        elif isinstance(o, list):
            for i, v in enumerate(o):
                walk(v, f'{path}[{i}]')
        elif isinstance(o, str) and ('.m3u8' in o or '.mp4' in o):
            print(f'{path} = {o[:200]}')
    walk(d)
except Exception as e:
    print('not json:', e)
PY
done
