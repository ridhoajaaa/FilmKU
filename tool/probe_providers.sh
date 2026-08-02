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
#
# Verdicts are written back to tool/source_health.json (data-driven source
# health — see README's Stream Source Pipeline section), so the README no
# longer needs hand-edited health notes per release.
set -u

CHROME=/usr/bin/chromium
UA="Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

# The TMDB API key is read from the environment — deliberately NOT hardcoded
# (the repo is public; see README "Provide the API key").
TMDB_KEY="${TMDB_API_KEY:-}"
if [ -z "$TMDB_KEY" ]; then
  echo "ERROR: set TMDB_API_KEY (e.g. TMDB_API_KEY=xxx ./tool/probe_providers.sh)" >&2
  exit 1
fi

# Resolve a TMDB id if not given (use a trending movie).
if [ -n "${1:-}" ]; then
  MID="$1"
else
  MID=$(curl -s --max-time 15 "https://api.themoviedb.org/3/trending/movie/week?api_key=$TMDB_KEY" \
    | python3 -c 'import sys,json; r=json.load(sys.stdin).get("results",[]); print(r[0]["id"] if r else "155")' 2>/dev/null)
  MID=${MID:-155}
fi
echo "=== PROBING providers with TMDB id: $MID ==="

# Extract plain media URLs (m3u8/mp4) from an HTML file, or empty.
grep_media() {
  grep -o -iE 'https?://[^"'"'"' <>]+\.(m3u8|mp4)([^"'"'"' <>]*)?' "$1" 2>/dev/null | head -3
}

# record_verdict <VERDICT> — persists the probe's verdict to a sidecar file
# (/tmp/probe_<name>.verdict) that the health-JSON writer below reads
# VERBATIM, so the persisted health always matches what the script printed.
record_verdict() {
  printf '%s' "$1" > "/tmp/probe_${name}.verdict"
}

probe() {
  local name="$1" url="$2"
  # Clear any verdict sidecar from a previous run FIRST, so the health-JSON
  # writer below can only ever see THIS run's verdict (a stale sidecar would
  # otherwise survive an interrupted probe and be misread as fresh).
  rm -f "/tmp/probe_${name}.verdict"
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
        record_verdict ALIVE
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
    record_verdict ALIVE
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
    record_verdict PROBE-FAILED
    return
  fi
  if [ -n "$media" ]; then
    echo "DOM MEDIA FOUND:"
    echo "$media"
    echo "VERDICT: ALIVE (m3u8/mp4 in rendered DOM)"
    record_verdict ALIVE
    return
  fi
  # 4. Blob-url player check (player works but URL is blob: — NOT native-friendly)
  local blob
  blob=$(grep -c -iE 'blob:|mediaSource|videojs|hls\.js' /tmp/probe_${name}_dom.html 2>/dev/null || true)
  if [ "$blob" -gt 0 ]; then
    echo "VERDICT: WEBVIEW-ONLY (blob/HLS.js player, no plain URL — not native-friendly)"
    record_verdict WEBVIEW-ONLY
  else
    echo "VERDICT: DEAD (no media, no player) — but see caveat above; verify on-device before pruning"
    record_verdict DEAD
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

# --- Persist verdicts into tool/source_health.json (data-driven health) ---
# Each probe() call wrote its final verdict VERBATIM to a sidecar
# /tmp/probe_<name>.verdict (see record_verdict). We read those sidecars so
# the persisted health always matches what the script printed — no duplicate
# detection logic that could drift.
HEALTH="$ROOT/tool/source_health.json"
python3 - "$HEALTH" <<'PYEOF'
import json, os, sys, datetime

health_path = sys.argv[1]
health = {}
if os.path.exists(health_path):
    try:
        health = json.load(open(health_path))
    except Exception:
        health = {}
providers = health.setdefault('providers', {})
for name in ['vidlink', 'two_embed_skin', 'two_embed', 'vidsrc_to', 'vidsrc_su']:
    sidecar = f'/tmp/probe_{name}.verdict'
    v = ''
    if os.path.exists(sidecar):
        try:
            v = open(sidecar).read().strip()
        except Exception:
            v = ''
    if not v:
        v = 'PROBE-FAILED'
    entry = providers.setdefault(name, {})
    entry['verdict'] = v
    entry['lastChecked'] = datetime.date.today().isoformat()
    if v == 'ALIVE':
        entry['nativePlayable'] = entry.get('nativePlayable', True)
    if not entry.setdefault('notes', ''):
        entry['notes'] = 'Probed automatically by tool/probe_providers.sh — treat desktop DEAD with the on-device caveat.'
health['updated'] = datetime.date.today().isoformat()
json.dump(health, open(health_path, 'w'), indent=2, ensure_ascii=False)
print(f'health updated: {health_path} (sidecar verdicts)')
PYEOF
