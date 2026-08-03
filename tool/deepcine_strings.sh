#!/usr/bin/env bash
# DeepCine dex strings audit — find the streaming backend/method.
set -u
DEX=/tmp/all_dex.bin

echo "=== A. PLAYER LIBRARIES ==="
for s in 'ExoPlayer' 'media3' 'ijkplayer' 'libvlc' 'VLC' 'WebView' 'onShouldOverrideUrlLoading' 'android.webkit' 'M3U8' 'm3u8' 'HlsPlayer' 'AVPlayer'; do
  n=$(strings "$DEX" | grep -c -i "$s" 2>/dev/null || echo 0)
  echo "$s: $n"
done

echo
echo "=== B. UNIQUE HTTP HOSTS (top-level domains) ==="
strings "$DEX" | grep -oE 'https?://[a-zA-Z0-9.-]+' | sed 's#https\?://##' | sort | uniq -c | sort -rn | head -40

echo
echo "=== C. API-LIKE PATHS ==="
strings "$DEX" | grep -oE 'https?://[a-zA-Z0-9./_-]+' | grep -iE '/api|/v[0-9]|/stream|/movie|/embed|/source|/search' | sort -u | head -40

echo
echo "=== D. KNOWN PROVIDERS / EMBED FRAGMENTS ==="
strings "$DEX" | grep -oiE '(vidsrc|2embed|cineby|vidlink|suubmon|movie-web|meweb|cmovies|fmovie|flix|streamtape|doodstream|gogoanime|embed\.su|vidbinge|warezcdn|whvx|databasegdrive)' | sort | uniq -c | sort -rn | head -25

echo
echo "=== E. JSON KEY HINTS (stream payload shapes) ==="
for k in 'videoUrl' 'streamUrl' 'playUrl' 'm3u8' 'sourceUrl' 'downloadUrl' 'embedUrl' 'urlList' 'sources' 'subtitle' 'hlsUrl'; do
  n=$(strings "$DEX" | grep -c "$k" 2>/dev/null || echo 0)
  [ "$n" != "0" ] && echo "$k: $n"
done

echo
echo "=== F. TMDB / API KEYS ==="
strings "$DEX" | grep -oiE '(tmdb|themoviedb|api_key|apikey|apiKey)[a-zA-Z0-9_=:.]*' | sort -u | head -15
