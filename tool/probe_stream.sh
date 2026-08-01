#!/bin/bash
# Probe the captured m3u8 (from FILMKU_WEBVIEW_CAPTURE in logcat) to verify the
# stream itself is valid and decodable by a software decoder (ffmpeg).
UA='Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
TOKEN='eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJteS1hdXRoIiwiaWF0IjoxNzg1NTcwMzI5LCJuYmYiOjE3ODU1NzAzMjksImV4cCI6MTc4NTU4NDcyOSwiaXBfY2lkciI6IjE4MC4yNDkuMzYuMC8yNCJ9.qWk_pqcfwg1KteL0WEF2nza8yrQoMoKpxge7ph-JK28'
BASE='https://illimitableinkwell.site/pl/H4sIAAAAAAAAAw3NW3KCMBQA0C0BSTumM_7IQ8USJJqbx19I0NSkHexQwa6.PRs4xKLEmAHjDKPkkiIyrIxZDa_ugnqTWPzWQkQ6TD.nnWsY7J9Cxsd7Uh0avswM3J2lV8S2DIat.2BSTy0fuSlrZBEDinw9lCrVSOfiHBeVjaXIydEJmglJDaTVydx82yVXbKLCnaygLTY5BFf3pX1RwiZaEK.kfdiU1ezcYPPbPfkt7ujZT1DSwn4Sxb.qjUG.0RGC4j7r8ylQOc6QLdpKtfAwSRp9.P.E4.T7kI13CCn0RZgN19WxW6__AEzdom0JAQAA'

echo '=== 1. master.m3u8 (variant list) ==='
curl -s --max-time 15 -A "$UA" -H "Referer: https://vidsrc.to/" "${BASE}/master.m3u8?token=${TOKEN}" -o /tmp/master.m3u8 -w 'HTTP=%{http_code} size=%{size_download}\n'
cat /tmp/master.m3u8 2>/dev/null | head -30

echo
echo '=== 2. index.m3u8 (segments) ==='
curl -s --max-time 15 -A "$UA" -H "Referer: https://vidsrc.to/" "${BASE}/0f23fcf79be0e63ab6d07c73d2dcf717/index.m3u8?token=${TOKEN}" -o /tmp/index.m3u8 -w 'HTTP=%{http_code} size=%{size_download}\n'
head -20 /tmp/index.m3u8 2>/dev/null

echo
echo '=== 3. ambil 1 segment + decode dengan ffmpeg (software) ==='
SEG=$(grep -v '^#' /tmp/index.m3u8 2>/dev/null | head -1)
echo "segment: $SEG"
if [ -n "$SEG" ]; then
  SEGURL=$(python3 -c "import sys,urllib.parse; print(urllib.parse.urljoin('${BASE}/0f23fcf79be0e63ab6d07c73d2dcf717/', sys.argv[1]))" "$SEG")
  curl -s --max-time 20 -A "$UA" -H "Referer: https://vidsrc.to/" "${SEGURL}?token=${TOKEN}" -o /tmp/seg.ts -w 'HTTP=%{http_code} size=%{size_download}\n'
  which ffmpeg >/dev/null 2>&1 && ffmpeg -v error -i /tmp/seg.ts -f null - 2>&1 | head -5 && echo 'FFMPEG_DECODE_OK' || echo 'NO_FFMPEG_OR_DECODE_FAIL'
  ls -la /tmp/seg.ts 2>/dev/null
fi

echo
echo '=== 4. ffprobe stream info ==='
which ffprobe >/dev/null 2>&1 && ffprobe -v error -show_entries stream=codec_name,width,height,profile -of default=noprint_wrappers=1 /tmp/seg.ts 2>&1 | head -8 || echo 'NO_FFPROBE'

echo
echo '=== 5. decode 5 detik dari segment pertama (ffmpeg software decode) ==='
[ -f /tmp/seg.ts ] && ffmpeg -v error -i /tmp/seg.ts -t 5 -f null - 2>&1 | head -3 && echo 'SW_DECODE_5S_OK'
