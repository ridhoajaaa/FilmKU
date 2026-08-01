#!/bin/bash
# Probe JARINGAN lengkap player 2embed swish: tangkap semua request (termasuk fetch/XHR)
# via Chromium net-log, lalu cari .m3u8/.mp4 yang benar-benar diminta player.
CHROME=/usr/bin/chromium
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
MID=969681

echo '=== 1. 2embed.skin -> swish id (dari iframe) ==='
# Ambil id swish dari halaman embed 2embed.skin
SWISH_ID=$(curl -s -L --max-time 10 -A "$UA" "https://www.2embed.skin/embed/movie/$MID" | grep -o 'streamsrcs\.2embed\.cc/swish?id=[^"&]*' | head -1 | sed 's/.*id=//')
echo "SWISH_ID=$SWISH_ID"

echo '=== 2. net-log probe swish player (real-time 25s) ==='
rm -f /tmp/netlog.json
timeout 45 "$CHROME" --headless=new --disable-gpu --no-sandbox \
  --user-agent="$UA" \
  --log-net-log=/tmp/netlog.json \
  --dump-dom "https://streamsrcs.2embed.cc/swish?id=$SWISH_ID&ref=mdrct" \
  > /tmp/swish_dom2.html 2>/dev/null
echo "DOM bytes: $(wc -c < /tmp/swish_dom2.html)"
echo "netlog bytes: $(wc -c < /tmp/netlog.json 2>/dev/null)"

echo '=== 3. URL m3u8/mp4 dalam netlog ==='
grep -o -iE 'https?://[^"\\ ]+\.(m3u8|mp4)[^"\\ ]*' /tmp/netlog.json 2>/dev/null | sort -u | head -10

echo '=== 4. hostnames yang diminta player (top 25) ==='
grep -o -E '"url":"https?://[^/"]+' /tmp/netlog.json 2>/dev/null | sed 's/"url":"//' | sort | uniq -c | sort -rn | head -25

echo '=== 5. app.js player — cari endpoint API ==='
curl -s -L --max-time 10 -A "$UA" 'https://streamsrcs.2embed.cc/js/app.js' -o /tmp/swish_app.js
echo "app.js bytes: $(wc -c < /tmp/swish_app.js 2>/dev/null)"
grep -o -E 'https?://[^"'"'"' ]{5,100}' /tmp/swish_app.js 2>/dev/null | sort -u | head -15
echo '--- fetch/ajax URL patterns in app.js ---'
grep -o -E '(fetch|ajax|\.get|\.post|XMLHttpRequest)\(["'"'"']?[^"'"'"')]{5,90}' /tmp/swish_app.js 2>/dev/null | sort -u | head -15
