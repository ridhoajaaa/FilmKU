#!/bin/bash
# Round 4 probe:
# A. 2embed JSON API -> plain m3u8/mp4 (native win?)
# B. swish player JS -> endpoint analysis
# C. DeepCine forensics round 2: wsSecret/wsTime algorithm, play API paths, backend liveness
# D. Android emulator availability (untuk MITM kalau perlu)
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
IMDB=tt0468569

echo '================ A. 2EMBED JSON API (native m3u8?) ================'
for api in \
  'https://api.2embed.cc/movie?imdb_id=' \
  'https://api.2embed.cc/v1/movie?imdb_id=' \
  'https://api.2embed.cc/v2/movie?imdb_id=' \
  'https://api.2embed.skin/movie?imdb_id=' \
  'https://api.2embed.skin/v1/movie?imdb_id=' \
  'https://api.2embed.cc/movie?tmdb_id=155' ; do
  url="${api}${IMDB}"
  [ "${api#*tmdb_id=}" != "$api" ] && url="$api"
  code=$(curl -s -L --max-time 10 -A "$UA" -o /tmp/r4.json -w '%{http_code}' "$url" 2>/dev/null)
  size=$(wc -c < /tmp/r4.json 2>/dev/null || echo 0)
  echo "--- $url [HTTP=$code size=$size]"
  if [ "$code" = "200" ] && [ "$size" -gt 50 ]; then
    echo "    top keys: $(python3 -c "import json;print(list(json.load(open('/tmp/r4.json')).keys()))" 2>/dev/null)"
    echo "    m3u8/mp4 URLs:"
    grep -o -iE 'https?://[^"\\ ]+\.(m3u8|mp4)([^"\\ ]*)' /tmp/r4.json 2>/dev/null | head -3
    echo "    stream-ish keys:"
    python3 - <<'PY' 2>/dev/null | head -14
import json
d=json.load(open('/tmp/r4.json'))
def walk(o,path=''):
    if isinstance(o,dict):
        for k,v in o.items():
            if any(w in k.lower() for w in ('stream','source','file','url','link','play','m3u8','mp4','hls')):
                s=str(v)
                print('   ',path+'/'+k,'=>',s[:120])
            walk(v,path+'/'+k)
    elif isinstance(o,list):
        for i,v in enumerate(o[:6]): walk(v,path+'['+str(i)+']')
walk(d)
PY
  fi
done

echo
echo '================ B. SWISH PLAYER JS (endpoint) ================'
for js in 'https://streamsrcs.2embed.cc/swishhg.js' 'https://streamsrcs.2embed.cc/swish.js'; do
  echo "--- $js"
  curl -s -L --max-time 10 -A "$UA" -o /tmp/r4js.js "$js" 2>/dev/null
  echo "  bytes: $(wc -c < /tmp/r4js.js 2>/dev/null)"
  grep -o -E 'https?://[a-zA-Z0-9._/-]{5,80}' /tmp/r4js.js 2>/dev/null | sort -u | head -8
  echo "  endpoint-ish paths:"
  grep -o -E '"[/][a-zA-Z0-9_./-]{4,40}"' /tmp/r4js.js 2>/dev/null | sort -u | grep -iE 'api|source|stream|play|video|get|hls' | head -10
done

echo
echo '================ C. DEEPCINE FORENSICS R2 ================'
if [ -f /tmp/all_dex.bin ]; then
echo '--- C1. signing/algorithm strings (wsSecret/wsTime/md5/sign) ---'
strings -n 5 /tmp/all_dex.bin 2>/dev/null | grep -iE 'wsSecret|wsTime|wsKey|sign|secret|md5|timestamp|expire' | sort -u | head -30
echo '--- C2. API paths (play/vod/detail/info) ---'
strings -n 6 /tmp/all_dex.bin 2>/dev/null | grep -E '/api/|/vod/|/play|/detail|/getinfo|/watch|/info' | sort -u | head -30
echo '--- C3. hostnames di dex ---'
strings -n 6 /tmp/all_dex.bin 2>/dev/null | grep -o -E '[a-z0-9]+\.[a-z0-9]+\.(com|net|io|cc|cn|xyz|top|app)' | sort -u | head -25
else
echo '  /tmp/all_dex.bin tidak ada - ekstrak ulang'
fi
echo '--- C4. backend liveness NOW ---'
for h in 'velvetreel.7nkznc.com' 'sdgc.e6r4r1.com'; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://$h/" 2>/dev/null)
  echo "  $h -> HTTP $code"
done

echo
echo '================ D. EMULATOR / TOOLS ====================='
which emulator adb mitmproxy 2>/dev/null || true
emulator -list-avds 2>/dev/null | head -5 || true
ls /opt/android-sdk/emulator/emulator 2>/dev/null && echo EMULATOR_BIN_OK || echo NO_EMULATOR
echo '--- adb device ---'
adb devices 2>/dev/null | tail -3
