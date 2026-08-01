#!/bin/bash
# Probe kandidat sumber stream plain m3u8/mp4 (2026) — sekali jalan, semua diuji.
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
MID=969681

probe_html() {
  local url="$1"
  local code size m3u8 mp4 title
  code=$(curl -s -L --max-time 10 -A "$UA" -o /tmp/p.html -w '%{http_code}' "$url" 2>/dev/null)
  size=$(wc -c < /tmp/p.html 2>/dev/null || echo 0)
  m3u8=$(grep -o -iE 'https?://[^" <>\x27]+\.m3u8[^" <>\x27]*' /tmp/p.html 2>/dev/null | head -1)
  mp4=$(grep -o -iE 'https?://[^" <>\x27]+\.mp4[^" <>\x27]*' /tmp/p.html 2>/dev/null | head -1)
  title=$(grep -o -E '<title>[^<]*</title>' /tmp/p.html 2>/dev/null | head -1 | sed 's/<[^>]*>//g')
  echo "URL=$url"
  echo "  CODE=$code SIZE=$size TITLE=${title:0:60}"
  echo "  M3U8=${m3u8:0:90}"
  echo "  MP4=${mp4:0:90}"
}

probe_json() {
  local url="$1"
  local code body
  code=$(curl -s -L --max-time 10 -A "$UA" -H 'Accept: application/json' -o /tmp/j.json -w '%{http_code}' "$url" 2>/dev/null)
  body=$(head -c 300 /tmp/j.json 2>/dev/null)
  echo "JSON_URL=$url CODE=$code BODY=${body:0:280}"
}

echo '=== 1. vidbinge.dev (sumber plain m3u8 terbesar 2024-2025) ==='
probe_html "https://vidbinge.dev/embed/movie/$MID"
probe_html "https://vidbinge.dev/embed/movie/$MID?autoPlay=true"

echo '=== 2. 2embed.skin (fork 2embed) ==='
probe_html "https://2embed.skin/embed/movie/$MID"

echo '=== 3. api.vidsrc.dev JSON API ==='
probe_json "https://api.vidsrc.dev/movies/$MID"
probe_json "https://api.vidsrc.dev/movies/$MID/sources"

echo '=== 4. movie-web backend providers (proxy) ==='
probe_json "https://api.movie-web.app/providers/movies/$MID"
probe_json "https://backend.movie-web.app/providers/movies/$MID"

echo '=== 5. kandidat lain yang belum diuji ==='
probe_html "https://vidsrc.xyz/embed/movie/$MID"
probe_html "https://embedder.net/e/movie/$MID"
probe_html "https://streamtape.com/e/movie/$MID"
probe_html "https://embed4u.xyz/embed/movie/$MID"
probe_html "https://filmxy.tv/embed/movie/$MID"

echo '=== 6. verifikasi cepat sumber lama (harus mati) ==='
probe_html "https://vidsrc.to/embed/movie/$MID"
probe_html "https://www.2embed.cc/embed/movie/$MID"
