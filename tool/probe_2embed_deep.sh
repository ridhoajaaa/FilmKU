#!/usr/bin/env bash
set -u
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
MID=1368337
EMBED="https://www.2embed.skin/embed/movie/$MID"

echo "=== 1. SHELL PAGE CONTENT (8KB) ==="
curl -s -L --max-time 15 -A "$UA" "$EMBED" -o /tmp/e2_shell.html
wc -c /tmp/e2_shell.html
echo "--- iframes / scripts / links ---"
grep -oE '<iframe[^>]*>|data-src="[^"]*"|src="[^"]*"|streamsrcs[^"\x27 ]*|swish[^"\x27 ]*' /tmp/e2_shell.html | sort -u | head -20
echo "--- readable body ---"
python3 - << 'PY'
import re
html = open('/tmp/e2_shell.html', encoding='utf-8', errors='replace').read()
text = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.S)
text = re.sub(r'<[^>]+>', ' ', text)
text = re.sub(r'\s+', ' ', text)
print(text[:800])
PY

echo
echo "=== 2. FOLLOW THE PLAYER IFrame ==="
# extract first iframe src
IFRAME=$(grep -oE '(data-src|src)="[^"]*(swish|stream|player|embed)[^"]*"' /tmp/e2_shell.html | head -1 | sed 's/^[a-z-]*="//;s/"$//')
echo "iframe candidate: $IFRAME"
if [ -n "$IFRAME" ]; then
  [[ "$IFRAME" == http* ]] || IFRAME="https://www.2embed.skin$IFRAME"
  echo "fetching: $IFRAME"
  curl -s -L --max-time 15 -A "$UA" -e "$EMBED" "$IFRAME" -o /tmp/e2_player.html
  wc -c /tmp/e2_player.html
  echo "--- media URLs in player ---"
  grep -oE 'https?://[^"'\'' <]+\.(m3u8|mp4)[^"'\'' <]*' /tmp/e2_player.html | sed 's/&amp;/\&/g' | sort -u | head -10
fi

echo
echo "=== 3. swish.js / player API endpoints ==="
for u in \
  "https://streamsrcs.2embed.cc/swish.js" \
  "https://streamsrcs.2embed.cc/swish" \
  "https://www.2embed.skin/player/swish.js" \
  "https://streamsrcs.2embed.cc/player.js"; do
  code=$(curl -s -o /tmp/e2_js.txt -w '%{http_code}' --max-time 12 -A "$UA" "$u" 2>/dev/null)
  size=$(wc -c < /tmp/e2_js.txt 2>/dev/null || echo 0)
  echo "$code  $size  $u"
done
echo "--- media/api URLs inside streamsrcs js ---"
for f in /tmp/e2_js.txt; do
  grep -oE 'https?://[a-zA-Z0-9./_-]+' "$f" 2>/dev/null | sort -u | head -15
done
