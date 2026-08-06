#!/usr/bin/env bash
# probe_vidnest.sh — render the VidNest player chain in headless Chromium and
# capture the real stream requests from the netlog.
#
# Usage: ./tool/probe_vidnest.sh [tmdb_id] [url]
#
# Chain under test (2026-08):
#   2embed.skin shell -> streamsrcs.2embed.cc/vnest -> cineby.hair/movie/{id}
#     -> VidNest player (vidnest.fun/movie/{id}, servers on new.vidnest.fun)
#
# Default URL is the direct VidNest movie player; pass a second arg to probe
# any other page (e.g. a new.vidnest.fun server page).
set -u

MID="${1:-634649}"
URL="${2:-https://vidnest.fun/movie/$MID}"
CHROME=/usr/bin/chromium
[ -x "$CHROME" ] || CHROME=$(command -v chromium || command -v google-chrome || command -v chromium-browser)
if [ -z "${CHROME:-}" ] || [ ! -x "$CHROME" ]; then
  echo "ERROR: no chromium/google-chrome binary found" >&2
  exit 1
fi
echo "chrome: $CHROME"
echo "url:    $URL"

UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'

echo
echo "=== 1. plain fetch (headers) ==="
curl -sIL -m 15 -A "$UA" "$URL" -o /dev/null -w 'HTTP %{http_code} final=%{url_effective}\n' 2>/dev/null || true
curl -sL -m 15 -A "$UA" "$URL" -o /tmp/vn_page.html -w 'HTTP %{http_code} size %{size_download}\n'
grep -oiE '(m3u8|\.mp4|vidnest[^" <]{0,50})' /tmp/vn_page.html | sort -u | head -10

echo
echo "=== 2. headless load (netlog capture) ==="
rm -f /tmp/vn_netlog.json
timeout 90 "$CHROME" --headless=new --disable-gpu --no-sandbox \
  --user-agent="$UA" --autoplay-policy=no-user-gesture-required \
  --log-net-log=/tmp/vn_netlog.json --net-log-capture-mode=IncludeSensitive \
  --virtual-time-budget=60000 "$URL" 2>/dev/null > /dev/null
echo "netlog bytes: $(wc -c < /tmp/vn_netlog.json 2>/dev/null || echo 0)"

echo
echo "=== 3. media URLs requested (.m3u8 / .mp4) ==="
grep -oE '"url":"https://[^"]*\.(m3u8|mp4)[^"]*"' /tmp/vn_netlog.json 2>/dev/null \
  | sed 's/&amp;/\&/g' | sort -u | head -15

echo
echo "=== 4. all unique hosts requested ==="
grep -oE '"url":"https://[^"]+"' /tmp/vn_netlog.json 2>/dev/null \
  | grep -oE 'https://[^/]+' | sort | uniq -c | sort -rn | head -20

echo
echo "=== 5. vidnest.fun / new.vidnest.fun requests ==="
grep -oE '"url":"https://[^"]*(vidnest|hollymoviehd|videasy|vidzee|nextgencloudfabric)[^"]*"' /tmp/vn_netlog.json 2>/dev/null \
  | sort -u | head -20
