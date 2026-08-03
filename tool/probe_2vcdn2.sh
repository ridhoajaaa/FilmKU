#!/usr/bin/env bash
set -u
CHROME=/usr/bin/chromium
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
MID=1368337
PLAYER="https://2vcdn.skin/e/$MID"

echo "=== 1. PLAYER PAGE FULL CONTENT ==="
curl -s -L --max-time 15 -A "$UA" -e "https://www.2embed.skin/embed/movie/$MID" "$PLAYER" -o /tmp/2v_player.html
wc -c /tmp/2v_player.html
cat /tmp/2v_player.html | head -c 1200
echo

echo
echo "=== 2. RENDER HEADLESS + NETLOG (catch real stream request) ==="
rm -f /tmp/2v_netlog.json
timeout 75 "$CHROME" --headless=new --disable-gpu --no-sandbox \
  --user-agent="$UA" --autoplay-policy=no-user-gesture-required \
  --log-net-log=/tmp/2v_netlog.json --net-log-capture-mode=IncludeSensitive \
  --virtual-time-budget=50000 "$PLAYER" 2>/dev/null > /dev/null
echo "netlog bytes: $(wc -c < /tmp/2v_netlog.json 2>/dev/null || echo 0)"

echo "--- media URLs requested ---"
grep -oE '"url":"https://[^"]*\.(m3u8|mp4)[^"]*"' /tmp/2v_netlog.json 2>/dev/null | sort -u | head -10
echo "--- all unique hosts requested ---"
grep -oE '"url":"https://[^"]+"' /tmp/2v_netlog.json 2>/dev/null | grep -oE 'https://[^/]+' | sort | uniq -c | sort -rn | head -15
