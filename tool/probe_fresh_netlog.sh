#!/usr/bin/env bash
# DECISIVE v2: real-time netlog -> fresh signed URL -> curl IMMEDIATELY.
set -u
CHROME=/usr/bin/chromium
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
MID=1368337
EMBED="https://vidlink.pro/movie/$MID"
rm -f /tmp/vl_fresh_netlog.json

echo "=== 1. CHROMIUM + NETLOG (real-time requests) ==="
timeout 75 "$CHROME" --headless=new --disable-gpu --no-sandbox \
  --user-agent="$UA" --autoplay-policy=no-user-gesture-required \
  --log-net-log=/tmp/vl_fresh_netlog.json --net-log-capture-mode=IncludeSensitive \
  --virtual-time-budget=50000 "$EMBED" 2>/dev/null > /dev/null
echo "netlog bytes: $(wc -c < /tmp/vl_fresh_netlog.json 2>/dev/null || echo 0)"

echo "=== 2. EXTRACT REQUESTED MP4 URLS (real-time) ==="
python3 - << 'PY'
import re, json, urllib.parse
raw = open('/tmp/vl_fresh_netlog.json', encoding='utf-8', errors='replace').read()
urls = set()
for m in re.finditer(r'"url":"(https://[^"]*?\.mp4[^"]*)"', raw):
    u = m.group(1).replace('\\/', '/').replace('\\u0026', '&').replace('&amp;', '&')
    # only keep ones that are genuinely from the vidlink CDN family
    if 'suubmon' in u or 'noir' in u or 'mp/' in u:
        urls.add(u)
for i, u in enumerate(sorted(urls)[:6]):
    q = urllib.parse.parse_qs(urllib.parse.urlparse(u).query)
    print(f'URL{i}: {u[:170]}')
    print(f'      t={q.get("t",["?"])[0]}')
open('/tmp/vl_fresh_neturls.txt', 'w').write('\n'.join(sorted(urls)))
print(f'TOTAL: {len(urls)}')
PY

echo "=== 3. CURL FRESH REQUESTED URL IMMEDIATELY ==="
i=0
while IFS= read -r u; do
  i=$((i+1))
  code=$(curl -s -L -o /tmp/fresh_body.bin -w '%{http_code}' --max-time 25 \
    -A "$UA" -e "$EMBED" -H 'Origin: https://vidlink.pro' "$u" 2>/dev/null)
  type=$(file -b --mime-type /tmp/fresh_body.bin 2>/dev/null)
  size=$(wc -c < /tmp/fresh_body.bin 2>/dev/null || echo 0)
  echo "NET_URL$i code=$code type=$type bytes=$size"
  echo "$u" | head -c 130; echo
done < /tmp/vl_fresh_neturls.txt

echo "=== done ==="
