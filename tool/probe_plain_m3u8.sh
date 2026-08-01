#!/bin/bash
# probe_plain_m3u8.sh — probe candidate plain-m3u8/mp4 sources for a TMDB id.
#
# Goal: find sources that serve a DIRECT .m3u8/.mp4 URL (usable by the native
# player) WITHOUT browser JavaScript / anti-bot. Each candidate is fetched
# with curl (mobile UA), and its raw response is grepped for plain media URLs.
# Output: per-candidate HTTP code, body size, and any direct media URLs found.
MID=${MID:-155}   # The Dark Knight — well-known, available everywhere
UA="Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

check() { # $1=label  $2=url  [$3=extra curl args]
  local label="$1" url="$2"; shift 2
  local html code
  html=$(curl -s -L --max-time 15 -A "$UA" "$@" "$url" 2>/dev/null)
  code=$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 15 -A "$UA" "$@" "$url" 2>/dev/null)
  local n
  n=$(echo "$html" | grep -o -iE 'https?://[^"'"'"' <>]+\.(m3u8|mp4)' | head -3)
  echo "--- $label ---"
  echo "  $url"
  echo "  HTTP $code | body ${#html} bytes"
  if [ -n "$n" ]; then
    echo "  MEDIA URLS:"
    echo "$n" | sed 's/^/    /'
  else
    echo "  (no plain m3u8/mp4 in raw response)"
  fi
}

echo "=== TMDB id: $MID ==="
echo

echo "### A. Known embed pages (expect JS-only; baseline)"
check "vidsrc.to"      "https://vidsrc.to/embed/movie/$MID"
check "vidsrc.su"      "https://vidsrc.su/embed/movie/$MID"
check "2embed.skin"    "https://www.2embed.skin/embed/movie/$MID"
check "2embed.cc"      "https://www.2embed.cc/embed/movie/$MID"
check "vidlink.pro"    "https://vidlink.pro/movie/$MID"

echo
echo "### B. JSON/API-style sources that may return direct m3u8"
check "vidsrc.net"     "https://vidsrc.net/embed/movie/$MID"
check "vidsrc.xyz"     "https://vidsrc.xyz/embed/movie/$MID"
check "vidsrc.pm"      "https://vidsrc.pm/embed/movie/$MID"
check "vidsrc.icu"     "https://vidsrc.icu/embed/movie/$MID"
check "embed.su"       "https://embed.su/embed/movie/$MID"
check "multiembed"     "https://multiembed.mov/directstream.php?tmdb=$MID"
check "smashystream"   "https://player.smashy.stream/movie/tmdb/$MID"
check "moviesapi"      "https://moviesapi.club/tmdb/movie-$MID"

echo
echo "### C. JSON API endpoints (vidsrc.xyz API family)"
check "vidsrc.xyz api" "https://vidsrc.xyz/api/movies/$MID"
check "vidsrc.net api" "https://vidsrc.net/api/movie/$MID"
check "embedapi"       "https://embedapi.xyz/api/movie?id=$MID"

echo
echo "### D. mov-cli / movie-web provider style (superembed, dopebox, etc)"
check "superembed"     "https://multiembed.mov/?video_id=$MID&tmdb=1"
check "dopebox"        "https://www.dopebox.to/movie/$MID"
check "fmovies"        "https://fmovies.ps/movie/$MID"
check "lookmovie"      "https://lookmovie2.to/movies/view/$MID"

echo
echo "### DONE ==="
