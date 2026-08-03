#!/usr/bin/env bash
# DECISIVE: is vidlink's 428 token expiry or hard anti-bot?
# Fresh page -> fresh signed URL -> curl IMMEDIATELY.
set -u
CHROME=/usr/bin/chromium
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
MID=1368337
EMBED="https://vidlink.pro/movie/$MID"

echo "=== 1. RENDER FRESH VIDLINK PAGE ==="
timeout 70 "$CHROME" --headless=new --disable-gpu --no-sandbox \
  --virtual-time-budget=45000 --user-agent="$UA" --dump-dom "$EMBED" \
  2>/dev/null > /tmp/vl_fresh_dom.html
echo "dom bytes: $(wc -c < /tmp/vl_fresh_dom.html)"

echo "=== 2. EXTRACT FRESH SIGNED URL ==="
python3 - << 'PY'
import re, urllib.parse
html = open('/tmp/vl_fresh_dom.html', encoding='utf-8', errors='replace').read()
urls = set()
for m in re.finditer(r'https?:\\/\\/[^"\'\\s<>]+?\\.mp4[^"\'\\s<>]*', html, re.I):
    u = m.group(0).replace('\\/', '/').replace('&amp;', '&')
    path = u.split('?')[0].split('#')[0].rstrip('/').lower()
    if path.endswith('.mp4'):
        urls.add(u)
for i, u in enumerate(sorted(urls)[:5]):
    q = urllib.parse.parse_qs(urllib.parse.urlparse(u).query)
    print(f'URL{i}: {u[:170]}')
    print(f'      t={q.get("t",["?"])[0]} headers={q.get("headers",["?"])[0][:40]}')
open('/tmp/vl_fresh_urls.txt', 'w').write('\n'.join(sorted(urls)))
print(f'TOTAL: {len(urls)}')
PY

echo "=== 3. CURL FRESH URL IMMEDIATELY (app headers) ==="
i=0
while IFS= read -r u; do
  i=$((i+1))
  start=$(date +%s)
  code=$(curl -s -L -o /tmp/fresh_body.bin -w '%{http_code}' --max-time 25 \
    -A "$UA" -e "$EMBED" -H 'Origin: https://vidlink.pro' "$u" 2>/dev/null)
  end=$(date +%s)
  type=$(file -b --mime-type /tmp/fresh_body.bin 2>/dev/null)
  size=$(wc -c < /tmp/fresh_body.bin 2>/dev/null || echo 0)
  echo "FRESH_URL$i code=$code type=$type bytes=$size (took $((end-start))s)"
  echo "$u" | head -c 130; echo
done < /tmp/vl_fresh_urls.txt

echo "=== done ==="
