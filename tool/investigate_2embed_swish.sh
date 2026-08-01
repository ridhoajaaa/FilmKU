#!/bin/bash
# investigate_2embed_swish.sh — trace the 2embed player chain to find a
# direct-m3u8 API endpoint. 2embed is the ONLY source verified alive from this
# network (HTTP 200 + correct title), and its player lives at
# streamsrcs.2embed.cc/swish — the internal API it calls may return a plain
# m3u8 that the native player can use directly.
MID=${MID:-155}
UA="Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

echo "=== 1. EMBED PAGE (2embed.skin) ==="
EMBED="https://www.2embed.skin/embed/movie/$MID"
html=$(curl -s -L --max-time 15 -A "$UA" "$EMBED" 2>/dev/null)
echo "bytes: ${#html}"
echo "--- iframes / player refs ---"
echo "$html" | grep -o -iE '(src|data-src|href)="[^"]*(swish|streamsrcs|embed|player)[^"]*"' | head -10
echo "--- script refs ---"
echo "$html" | grep -o -iE '<script[^>]*src="[^"]*"' | head -10

echo
echo "=== 2. PLAYER IFRAME (swish) ==="
# extract the swish/streamsrcs iframe URL
IFRAME=$(echo "$html" | grep -o -iE 'https?://[^"'"'"' <>]*?(swish|streamsrcs)[^"'"'"' <>]*' | head -1)
echo "iframe candidate: $IFRAME"
if [ -n "$IFRAME" ]; then
  ph=$(curl -s -L --max-time 15 -A "$UA" "$IFRAME" 2>/dev/null)
  echo "player bytes: ${#ph}"
  echo "--- player API/config refs (urls, fetch, .m3u8, /api/) ---"
  echo "$ph" | grep -o -iE 'https?://[^"'"'"' <>]*' | grep -iE 'api|m3u8|source|config|vidsrc|stream' | head -15
  echo "--- swish config id (window.SWISH / config=...) ---"
  echo "$ph" | grep -o -iE '(config|source_id|v_id|swish)[=:][^&"'"'"' ]{1,40}' | head -10
fi

echo
echo "=== 3. KNOWN SWISH API ENDPOINT PATTERNS (direct test) ==="
for u in \
  "https://streamsrcs.2embed.cc/swish/$MID" \
  "https://streamsrcs.2embed.cc/api/movie/$MID" \
  "https://streamsrcs.2embed.cc/swish/index.php?tmdb=$MID" \
  "https://www.2embed.skin/embed/movie/$MID?api=true"; do
  out=$(curl -s -L --max-time 12 -A "$UA" -w '\nHTTP:%{http_code}' "$u" 2>/dev/null)
  code=$(echo "$out" | tail -1)
  body=$(echo "$out" | head -n -1)
  echo "--- $u ---"
  echo "  $code | ${#body} bytes"
  echo "$body" | grep -o -iE '(https?:)?\\?/\\?/[^"'"'"' <>]+\\.(m3u8|mp4)' | head -3 | sed 's/^/    MEDIA: /'
done

echo
echo "=== DONE ==="
