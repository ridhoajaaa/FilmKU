#!/usr/bin/env bash
# probe_vidnest_server.sh — fetch the VidNest server endpoints
# (new.vidnest.fun/{server}/movie/{tmdb}) and inspect the response format.
#
# Usage: ./tool/probe_vidnest_server.sh [tmdb_id]
set -u

MID="${1:-634649}"
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
REF='https://vidnest.fun/movie/'$MID

for server in hollymoviehd videasy vidzee nextgencloudfabric; do
  url="https://new.vidnest.fun/$server/movie/$MID"
  echo "================================================================"
  echo "=== $url ==="
  code=$(curl -sL -m 20 -A "$UA" -e "$REF" -H 'Accept: application/json, text/plain, */*' -w '%{http_code}' -o /tmp/vn_srv.html "$url" 2>/dev/null)
  size=$(wc -c < /tmp/vn_srv.html)
  echo "HTTP $code size $size"
  echo "--- head (600 chars) ---"
  head -c 600 /tmp/vn_srv.html
  echo
  echo "--- media-ish strings ---"
  grep -oE '(m3u8|\.mp4|https://[a-zA-Z0-9./_-]+)' /tmp/vn_srv.html | sort -u | head -10
  echo
done
