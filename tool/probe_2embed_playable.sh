#!/usr/bin/env bash
# Verify 2embed.skin produces an mpv-playable (plain, non-anti-bot) URL.
# 1) chromium headless renders the embed page, 2) extract media URLs,
# 3) curl each with app-style headers -> expect 200 video bytes.
set -u
CHROME=/usr/bin/chromium
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
MID=1368337
EMBED="https://www.2embed.skin/embed/movie/$MID"

echo "=== 1. RENDER 2EMBED.SKIN (chromium headless) ==="
timeout 70 "$CHROME" --headless=new --disable-gpu --no-sandbox \
  --virtual-time-budget=45000 --user-agent="$UA" --dump-dom "$EMBED" \
  2>/dev/null > /tmp/dom_2embed_skin.html
echo "dom bytes: $(wc -c < /tmp/dom_2embed_skin.html)"

echo "=== 2. EXTRACT MEDIA URLS ==="
python3 - << 'PY'
import re
html = open('/tmp/dom_2embed_skin.html', encoding='utf-8', errors='replace').read()
urls = set()
for m in re.finditer(r'https?:\\/\\/[^"\'\\s<>]+?\\.(?:m3u8|mp4)[^"\'\\s<>]*', html, re.I):
    u = m.group(0).replace('\\/', '/').replace('&amp;', '&')
    path = u.split('?')[0].split('#')[0].rstrip('/').lower()
    if path.endswith('.m3u8') or path.endswith('.mp4'):
        urls.add(u)
for i, u in enumerate(sorted(urls)[:8]):
    print(f'URL{i}: {u[:200]}')
print(f'TOTAL: {len(urls)}')
open('/tmp/embed_urls.txt', 'w').write('\n'.join(sorted(urls)))
PY

echo "=== 3. CURL EACH URL (app headers: Referer+Origin+UA) ==="
EMBED_FOR_HEADER="https://www.2embed.skin/embed/movie/$MID"
i=0
while IFS= read -r u; do
  i=$((i+1))
  code=$(curl -s -L -o /tmp/embed_body.bin -w '%{http_code}' --max-time 25 \
    -A "$UA" -e "$EMBED_FOR_HEADER" -H "Origin: https://www.2embed.skin" "$u" 2>/dev/null)
  type=$(file -b --mime-type /tmp/embed_body.bin 2>/dev/null)
  size=$(wc -c < /tmp/embed_body.bin 2>/dev/null || echo 0)
  echo "URL$i code=$code type=$type bytes=$size"
  echo "$u" | head -c 120; echo
done < /tmp/embed_urls.txt

echo "=== done ==="
