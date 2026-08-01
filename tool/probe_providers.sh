#!/bin/bash
# probe_providers.sh — live-probe every stream provider in the FilmKU registry.
# For each provider: fetch the embed page (mobile UA), render it headless,
# and look for a playable m3u8/mp4 URL. Reports ALIVE / WEBVIEW-ONLY / DEAD.
#
# IMPORTANT CAVEAT: desktop chromium headless is NOT a faithful proxy for the
# on-device WebView. Anti-bot/fingerprint checks often make the desktop probe
# report DEAD for sources that DO work on the phone (vidsrc_to captured
# master.m3u8 on-device in ~26s while this desktop probe shows DEAD).
# NEVER prune a provider based on this probe alone — verify on-device via
# logcat (FILMKU_AUTOCAPTURE trace) before removing anything.
#
# Usage: ./tool/probe_providers.sh [tmdb_id]
set -u

CHROME=/usr/bin/chromium
UA="Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

# Resolve a TMDB id if not given (use a trending movie).
if [ -n "${1:-}" ]; then
  MID="$1"
else
  MID=$(curl -s --max-time 15 'https://api.themoviedb.org/3/trending/movie/week?api_key=497ddd1299fb3f83808649bbafa48d06' \
    | python3 -c 'import sys,json; r=json.load(sys.stdin).get("results",[]); print(r[0]["id"] if r else "155")' 2>/dev/null)
  MID=${MID:-155}
fi
echo "=== PROBING providers with TMDB id: $MID ==="

# Extract plain media URLs (m3u8/mp4) from an HTML file, or empty.
grep_media() {
  grep -o -iE 'https?://[^"'"'"' <>]+\.(m3u8|mp4)([^"'"'"' <>]*)?' "$1" 2>/dev/null | head -3
}

probe() {
  local name="$1" url="$2"
  echo
  echo "--- $name ($url) ---"
  # 1. Raw HTTP check
  local code size
  code=$(curl -s -L --max-time 15 -A "$UA" -o /tmp/probe_${name}.html -w '%{http_code}' "$url" 2>/dev/null)
  size=$(wc -c < /tmp/probe_${name}.html 2>/dev/null || echo 0)
  echo "HTTP $code, body ${size} bytes"

  # 1b. If the page is a shell with an iframe, resolve and probe the iframe URL.
  local iframe
  iframe=$(grep -o -iE '<iframe[^>]+src=[^ >]+' /tmp/probe_${name}.html 2>/dev/null | head -1 \
    | sed -E 's/.*src=["'"'"']?([^"'"'"' >]+).*/\1/' )
  if [ -n "$iframe" ]; then
    local iframe_url scheme host
    scheme=$(printf '%s' "$url" | sed -E 's|^(https?)://.*|\1|')
    host=$(printf '%s' "$url" | sed -E 's|^https?://([^/]+).*|\1|')
    case "$iframe" in
      http*) iframe_url="$iframe" ;;
      //*)   iframe_url="$scheme:$iframe" ;;
      /*)    iframe_url="$scheme://$host$iframe" ;;
      *)     iframe_url="" ;;
    esac
    if [ -n "$iframe_url" ]; then
      echo "iframe shell -> $iframe_url"
      curl -s -L --max-time 15 -A "$UA" -o /tmp/probe_${name}_iframe.html "$iframe_url" 2>/dev/null
      local im
      im=$(grep_media /tmp/probe_${name}_iframe.html)
      if [ -n "$im" ]; then
        echo "IFRAME MEDIA FOUND:"
        echo "$im"
        echo "VERDICT: ALIVE (plain URL in iframe page)"
        return
      fi
      # fall through: also render the iframe URL headless below
      url="$iframe_url"
    fi
  fi

  # 2. Raw body: direct m3u8/mp4 hits
  local raw_media
  raw_media=$(grep_media /tmp/probe_${name}.html)
  if [ -n "$raw_media" ]; then
    echo "RAW MEDIA FOUND:"
    echo "$raw_media"
    echo "VERDICT: ALIVE (plain URL in HTML)"
    return
  fi

  # 3. Headless render probe (virtual time budget so JS players can start)
  timeout 55 "$CHROME" --headless=new --disable-gpu --no-sandbox \
    --virtual-time-budget=40000 --user-agent="$UA" \
    --dump-dom "$url" 2>/dev/null > /tmp/probe_${name}_dom.html
  local dom_size media
  dom_size=$(wc -c < /tmp/probe_${name}_dom.html 2>/dev/null || echo 0)
  media=$(grep_media /tmp/probe_${name}_dom.html)
  echo "rendered DOM ${dom_size} bytes"
  if [ "$dom_size" -eq 0 ]; then
    echo "VERDICT: PROBE-FAILED (chromium produced nothing — anti-bot or network; NOT proof of death)"
    return
  fi
  if [ -n "$media" ]; then
    echo "DOM MEDIA FOUND:"
    echo "$media"
    echo "VERDICT: ALIVE (m3u8/mp4 in rendered DOM)"
    return
  fi
  # 4. Blob-url player check (player works but URL is blob: — NOT native-friendly)
  local blob
  blob=$(grep -c -iE 'blob:|mediaSource|videojs|hls\.js' /tmp/probe_${name}_dom.html 2>/dev/null || true)
  if [ "$blob" -gt 0 ]; then
    echo "VERDICT: WEBVIEW-ONLY (blob/HLS.js player, no plain URL — not native-friendly)"
  else
    echo "VERDICT: DEAD (no media, no player) — but see caveat above; verify on-device before pruning"
  fi
}

probe vidsrc_to    "https://vidsrc.to/embed/movie/$MID"
probe two_embed    "https://www.2embed.cc/embed/movie/$MID"
probe two_embed_skin "https://www.2embed.skin/embed/movie/$MID"
probe vidsrc_su    "https://vidsrc.su/embed/movie/$MID"
probe vidlink      "https://vidlink.pro/movie/$MID"

echo
echo "=== DONE ==="
echo "NOTE: desktop DEAD does NOT mean on-device DEAD (anti-bot). Confirm with logcat before pruning."
