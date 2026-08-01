#!/bin/bash
# probe_cdn_hosts.sh — definitive network-reachability check.
#
# The phone logcat (2026-08-01 18:09) showed the hidden capture WebView DID
# start the player, but its stream request to the tokenized vidsrc.to CDN was
# refused: 2e7q227lznx.b2iy3ce7tibff9.cfd -> ERR_CONNECTION_REFUSED. If those
# hosts are also unreachable from the laptop network, it's a region/ISP block
# of the source CDNs — no app-side change can fix that.
UA="Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

echo "=== 1. TOKENIZED CDN HOSTS FROM PHONE LOGCAT ==="
for host in \
  "2e7q227lznx.b2iy3ce7tibff9.cfd/kfx3p7pvQ56yJYvZO7Xr/VvMrO" \
  "u9oiqkb.c45g38uu3ruk8ftb1bo3v.rest/kqz84QgG6R4BXGhwpH/VvMrO" \
  "miranda.dutchedkaildil.cyou" \
  "cloudnestra.com" \
  "llvpn.com" \
  "adexchangerapid.com"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -A "$UA" "https://$host" 2>/dev/null)
  echo "https://$host -> HTTP $code"
done

echo
echo "=== 2. CURRENT SOURCES: plain .m3u8/.mp4 reachable from THIS network? ==="
MID=155
for url in \
  "https://vidsrc.to/embed/movie/$MID" \
  "https://www.2embed.cc/embed/movie/$MID" \
  "https://www.2embed.skin/embed/movie/$MID" \
  "https://vidsrc.su/embed/movie/$MID" \
  "https://vidlink.pro/movie/$MID"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 -A "$UA" -L "$url" 2>/dev/null)
  echo "GET $url -> HTTP $code"
done

echo
echo "=== 3. Does ANY embed page contain a plain m3u8/mp4 URL in raw HTML? ==="
for url in \
  "https://vidsrc.to/embed/movie/$MID" \
  "https://www.2embed.cc/embed/movie/$MID" \
  "https://www.2embed.skin/embed/movie/$MID" \
  "https://vidsrc.su/embed/movie/$MID" \
  "https://vidlink.pro/movie/$MID"; do
  n=$(curl -s --max-time 12 -A "$UA" -L "$url" 2>/dev/null \
    | grep -o -iE 'https?://[^"'"'"' <>]+\.(m3u8|mp4)' | wc -l)
  echo "$url -> raw m3u8/mp4 occurrences: $n"
done

echo
echo "=== 4. vidsrc.to direct-stream style CDN (VvMrO token) from this network ==="
html=$(curl -s --max-time 12 -A "$UA" -L "https://vidsrc.to/embed/movie/$MID" 2>/dev/null)
echo "vidsrc.to page bytes: ${#html}"
echo "$html" | grep -o -iE '[a-z0-9]{10,}\.[a-z0-9]{2,}\.[a-z]{2,4}/[A-Za-z0-9]{10,}' | head -5

echo
echo "=== 5. IS THE TOKENIZED CDN URL ACTUALLY VIDEO? (Range GET, -L, Referer+Origin) ==="
# Follow redirects (-L) and send both Referer + Origin (matching what the
# app's native player sends) so a signed/redirecting CDN isn't mislabelled.
for u in \
  "https://2e7q227lznx.b2iy3ce7tibff9.cfd/kfx3p7pvQ56yJYvZO7Xr/VvMrO"; do
  out=$(curl -s -o /dev/null --max-time 10 -A "$UA" -L \
    -H 'Referer: https://vidsrc.to/' -H 'Origin: https://vidsrc.to' \
    -w '%{http_code} %{content_type} %{size_download}' -r 0-2047 "$u" 2>/dev/null)
  echo "$u -> ${out:-000 (curl failed / no response)}"
done

# Interpretation note (self-documenting):
#   000 = unreachable (DNS fail / conn refused / timeout) — network/region block
#   403 = reachable but blocked at HTTP layer
#   200/206 + video/* = the CDN IS serving video from this network

echo
echo "=== DONE ==="
