#!/bin/bash
# Probe final: apakah player swish (2embed) mengeluarkan m3u8/mp4 dengan autoplay diizinkan,
# dan endpoint API apa yang dipanggilnya. Kalau ada endpoint stream langsung -> sumber native murni.
CHROME=/usr/bin/chromium
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
MID=155

echo '=== 1. path yang diminta ke streamsrcs.2embed.cc (dari netlog movie 155) ==='
grep -o -E '"url":"https://streamsrcs\.2embed\.cc[^"]*' /tmp/net2.json 2>/dev/null | sed 's/"url":"//' | sort -u | head -10

echo '=== 2. app.js: cari swish/stream/source/embed endpoint ==='
curl -s -L --max-time 10 -A "$UA" 'https://streamsrcs.2embed.cc/js/app.js' -o /tmp/swish_app.js
grep -o -E '(swish|stream|source|embed|player|get|ajax)[^;]{0,80}' /tmp/swish_app.js 2>/dev/null | grep -iE 'url|\.php|/v|json|data' | head -15

echo '=== 3. probe autoplay: dump-dom + netlog dengan autoplay diizinkan (movie 155) ==='
rm -f /tmp/net3.json
timeout 50 "$CHROME" --headless=new --disable-gpu --no-sandbox \
  --user-agent="$UA" \
  --autoplay-policy=no-user-gesture-required \
  --log-net-log=/tmp/net3.json \
  --virtual-time-budget=30000 \
  --dump-dom 'https://streamsrcs.2embed.cc/swish?id=4p2e9l0tqd8m&ref=mdrct' \
  > /tmp/swish3.html 2>/dev/null
echo "DOM: $(wc -c < /tmp/swish3.html)"
echo '--- video/source in DOM ---'
grep -o -E '<video[^>]*>|<source[^>]*>' /tmp/swish3.html | head -4
echo '--- m3u8/mp4 in netlog ---'
grep -o -iE 'https?://[^"\\ ]+\.(m3u8|mp4)[^"\\ ]*' /tmp/net3.json 2>/dev/null | sort -u | head -10
echo '--- semua host diminta (top 15) ---'
grep -o -E '"url":"https?://[^/"]+' /tmp/net3.json 2>/dev/null | sed 's/"url":"//' | sort | uniq -c | sort -rn | head -15
