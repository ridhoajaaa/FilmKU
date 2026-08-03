#!/usr/bin/env bash
set -u
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
MID=1368337

echo "=== 1. swish player page (full) ==="
curl -s -L --max-time 15 -A "$UA" "https://streamsrcs.2embed.cc/swish?id=$MID" -o /tmp/swish.html
wc -c /tmp/swish.html
echo "--- framesrc / iframe / js urls ---"
grep -oE '(framesrc|data-src|src)="[^"]*"' /tmp/swish.html | sort -u | head -15
echo "--- script srcs ---"
grep -oE 'src="[^"]*\.js[^"]*"' /tmp/swish.html | sort -u | head -10

echo
echo "=== 2. the myUrl (what gets prefixed by 2vcdn.skin/e/) ==="
MYURL=$(grep -oE '#framesrc.attr\(.src.\), ?[^;]*' /tmp/swish.html | head -1)
echo "pattern: $MYURL"
# try common relative srcs
FRAME=$(grep -oE 'src="(\.?/?[a-zA-Z0-9_?=&./-]+)"' /tmp/swish.html | sed 's/src="//;s/"$//' | grep -viE '\.js|\.css|\.png|\.gif|\.svg|about:' | head -3)
echo "candidates: $FRAME"

echo
echo "=== 3. direct 2vcdn.skin probes ==="
for u in \
  "https://2vcdn.skin/e/$MID" \
  "https://2vcdn.skin/e/movie/$MID" \
  "https://2vcdn.skin/e/index.php?id=$MID" \
  "https://2vcdn.skin/"; do
  code=$(curl -s -o /tmp/2v.html -w '%{http_code}' --max-time 12 -A "$UA" "$u" 2>/dev/null)
  size=$(wc -c < /tmp/2v.html 2>/dev/null || echo 0)
  echo "$code  $size  $u"
  if [ "$code" = "200" ]; then
    echo "--- media urls in $u ---"
    grep -oE 'https?://[^"'\'' <]+\.(m3u8|mp4)[^"'\'' <]*' /tmp/2v.html | sed 's/&amp;/\&/g' | sort -u | head -8
    echo "--- js urls ---"
    grep -oE 'src="[^"]*"' /tmp/2v.html | sort -u | head -8
  fi
done

echo
echo "=== 4. try swish with the real session id format (swish?id=pt1rq75ysb61) ==="
curl -s -L --max-time 15 -A "$UA" "https://streamsrcs.2embed.cc/swish?id=pt1rq75ysb61&ref=mdrct" -o /tmp/swish2.html
wc -c /tmp/swish2.html
grep -oE 'src="[^"]*"' /tmp/swish2.html | sort -u | head -12
grep -oE 'https?://[^"'\'' <]+' /tmp/swish2.html | sort -u | head -12
