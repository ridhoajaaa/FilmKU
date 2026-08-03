#!/usr/bin/env bash
# Probe the EXACT vidlink CDN URL captured on-device (syslog 2026-08-03):
# url=...noir.suubmon.store/...mp4?sign=...&t=...&headers=%7B%7D&host=...
# Question: which HTTP headers make the CDN accept it? If NONE, mpv can
# never play this URL and the app must not hand it to mpv.
set -u

URL='https://noir.suubmon.store/mp/resource/h265/61091c2544be10770e718dba71459d87.mp4?sign=3276f848ed10b15821933c7ee0868403&t=1785546276&headers=%7B%7D&host=https%3A%2F%2Fbcdn.hakunaymatata.com'
EMBED='https://vidlink.pro/movie/1368337'
UA='Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'

probe() {
  local label="$1"; shift
  local code type size
  code=$(curl -s -L -o /tmp/probe_body.bin -w '%{http_code}' --max-time 20 \
    -A "$UA" -e "$EMBED" -H 'Origin: https://vidlink.pro' "$@" "$URL" 2>/dev/null)
  type=$(curl -s -L -o /dev/null -w '%{content_type}' --max-time 20 \
    -A "$UA" -e "$EMBED" -H 'Origin: https://vidlink.pro' "$@" "$URL" 2>/dev/null)
  size=$(wc -c < /tmp/probe_body.bin 2>/dev/null || echo 0)
  printf '%-42s code=%s type=%s bytes=%s\n' "$label" "$code" "$type" "$size"
}

echo "=== 1. app-style headers (Referer+Origin+UA) ==="
probe 'app headers'

echo "=== 2. plain (no headers) ==="
probe 'no headers' -H 'Accept: */*'

echo "=== 3. browser-complete header set ==="
probe 'full browser' \
  -H 'Accept: video/webm,video/ogg,video/mp4,*/*' \
  -H 'Accept-Language: en-US,en;q=0.9' \
  -H 'Sec-Fetch-Dest: video' \
  -H 'Sec-Fetch-Mode: no-cors' \
  -H 'Sec-Fetch-Site: cross-site' \
  -H 'Accept-Encoding: identity' \
  --compressed

echo "=== 4. with cookie jar from embed page ==="
curl -s -L --max-time 20 -A "$UA" -c /tmp/probe_cj.txt -o /dev/null "$EMBED" 2>/dev/null
probe 'embed cookies' -b /tmp/probe_cj.txt

echo "=== 5. Range request (first 1MB, like a player) ==="
probe 'range 0-1MB' -H 'Range: bytes=0-1048575'

echo "=== 6. filled headers template (what the JS player would send) ==="
FILLED_HEADERS='%7B%22Referer%22%3A%22https%3A%2F%2Fvidlink.pro%2F%22%2C%22Origin%22%3A%22https%3A%2F%2Fvidlink.pro%22%7D'
URL_FILLED="${URL/headers=%7B%7D/headers=$FILLED_HEADERS}"
code=$(curl -s -L -o /tmp/probe_body2.bin -w '%{http_code}' --max-time 20 \
  -A "$UA" -e "$EMBED" -H 'Origin: https://vidlink.pro' "$URL_FILLED" 2>/dev/null)
echo "filled-template headers (URL rewritten): code=$code bytes=$(wc -c < /tmp/probe_body2.bin 2>/dev/null || echo 0)"

echo "=== 7. HTTP/1.1 forced (mpv default is http/1.1) ==="
probe 'http1.1' --http1.1

echo "=== 8. HTTP/2 forced (browser default) ==="
probe 'http2' --http2

echo "=== done ==="
