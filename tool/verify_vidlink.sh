#!/bin/bash
# verify_vidlink.sh — check whether vidlink.pro actually serves a plain,
# directly-playable .mp4 (native-friendly) for multiple TMDB ids.
#
# IMPORTANT: a signed/tokenized CDN URL (sign=, t=, headers=) often rejects
# HEAD (-I) and Range requests with 403/405/428 while STILL streaming fine via
# a browser session (which carries cookies the native player does not have).
# So a 403/428 here does NOT prove the source is dead for WebView use — it
# proves it is NOT directly playable by the native player without those
# browser credentials. Verify on-device before pruning.
#
# Usage: ./tool/verify_vidlink.sh [id1 id2 id3 ...]
set -u

CHROME=/usr/bin/chromium
UA="Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

if [ $# -eq 0 ]; then
  set -- 969681 155 693134 157336 299534
fi

for MID in "$@"; do
  echo
  echo "=== vidlink.pro/movie/$MID ==="
  timeout 55 "$CHROME" --headless=new --disable-gpu --no-sandbox \
    --virtual-time-budget=40000 --user-agent="$UA" \
    --dump-dom "https://vidlink.pro/movie/$MID" 2>/dev/null > /tmp/vl_${MID}.html
  sz=$(wc -c < /tmp/vl_${MID}.html 2>/dev/null || echo 0)
  echo "DOM: ${sz} bytes"

  # Process substitution: runs the while-loop in the current shell so `found`
  # actually propagates (a plain pipe would fork a subshell where it cannot).
  found=0
  while IFS= read -r u; do
    found=1
    echo "MEDIA: $u"
    # Single Range GET (as a player would) with Referer — one consistent
    # observation of both status and content-type, no wasted full download.
    read -r code ctype < <(curl -s -o /dev/null --max-time 15 -A "$UA" \
      -H 'Referer: https://vidlink.pro/' \
      -w '%{http_code} %{content_type}' -r 0-2047 "$u" 2>/dev/null)
    echo "  GET status: $code | content-type: $ctype"
    case "$ctype" in
      video/*|application/octet-stream|application/x-mpegURL|application/vnd.apple.mpegurl)
        echo "  VERDICT: likely PLAYABLE natively" ;;
      text/html*)
        echo "  VERDICT: got HTML ($code) — challenge/error page, NOT directly playable natively" ;;
      *)
        if [ "$code" = "200" ] || [ "$code" = "206" ]; then
          echo "  VERDICT: HTTP $code — likely playable (no video/ type reported)"
        else
          echo "  VERDICT: HTTP $code — browser-credential protected; NOT native-friendly, verify on-device before pruning"
        fi ;;
    esac
  done < <(grep -o -iE 'https?://[^"'"'"' <>]+\.(m3u8|mp4)([^"'"'"' <>]*)?' /tmp/vl_${MID}.html 2>/dev/null | sed 's/&amp;/\&/g' | head -2)

  if [ "$found" -eq 0 ]; then
    echo "(no plain m3u8/mp4 URL found for this movie — vidlink may fall back to blob/HLS)"
  fi
done
echo
echo "=== DONE ==="
