#!/usr/bin/env bash
# probe_vidnest_cipher.sh — hunt the VidNest response decryption logic.
#
# new.vidnest.fun/{server}/movie/{tmdb} returns {"data":"...","encrypted":true}
# with a custom-encoded payload. The decoder lives in the vidnest.fun Next.js
# bundle — download the chunks and grep for cipher primitives.
set -u

UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
mkdir -p /tmp/vnchunks
cd /tmp/vnchunks

for chunk in \
  00cb8966bcf22375 31dd2cd50f2a288b 66b231c2403f619d 69be39811437728d \
  6c30b25e2bb0f61b 6cbc633dfe24255e 744355e03808d4c7 9bd6e41ec62ebb62 \
  a3f6c22d97a69088 a6dad97d9634a72d ada9fd57d4c2e0ae b5dc6c688de67194 \
  d4cf4caae891f664 ff1a16fafef87110 turbopack-b527ebc3afe4110c; do
  if [ ! -s "$chunk.js" ]; then
    curl -sL -m 15 -A "$UA" "https://vidnest.fun/_next/static/chunks/$chunk.js" -o "$chunk.js"
  fi
done
ls -la | head -20

echo
echo "=== chunks mentioning 'encrypted' ==="
grep -l 'encrypted' *.js 2>/dev/null

echo
echo "=== decrypt-ish primitives (per chunk) ==="
for f in *.js; do
  hits=$(grep -oE 'encrypted|decrypt|fromCharCode|charCodeAt|\.split\(""\)|\.reverse\(\)|atob\(|String\.fromCharCode' "$f" 2>/dev/null | sort -u | tr '\n' ' ')
  if [ -n "$hits" ]; then
    echo "$f: $hits"
  fi
done

echo
echo "=== context around 'encrypted' (first 2 hits) ==="
for f in $(grep -l 'encrypted' *.js 2>/dev/null); do
  echo "--- $f ---"
  grep -oE '.{300}encrypted.{400}' "$f" | head -2
done
