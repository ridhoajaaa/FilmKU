#!/bin/bash
# Probe swishhg.js: cari endpoint API stream langsung yang dipanggil player swish.
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
echo '=== 1. swishhg.js ==='
curl -s -L --max-time 10 -A "$UA" 'https://streamsrcs.2embed.cc/swishhg.js' -o /tmp/swishhg.js
echo "bytes: $(wc -c < /tmp/swishhg.js 2>/dev/null)"
echo '--- URL endpoints ---'
grep -o -E 'https?://[^" ]{5,120}' /tmp/swishhg.js 2>/dev/null | sort -u | head -15
echo '--- path/api patterns ---'
grep -o -E '(/api/[^"'"'"' ]{3,80}|/[a-z_]+\.php[^"'"'"' ]{0,60}|getSources|getSourcesV2|loadS[^"'"'"' ]{0,40})' /tmp/swishhg.js 2>/dev/null | sort -u | head -15

echo
echo '=== 2. halaman swish: semua inline script ==='
python3 -c "
import re
t = open('/tmp/swish3.html', errors='ignore').read()
blocks = re.findall(r'<script[^>]*>(.*?)</script>', t, re.S)
print('script blocks:', len(blocks))
for i, b in enumerate(blocks):
    if any(w in b.lower() for w in ('fetch', 'ajax', 'source', 'stream', 'http')):
        print('--- block', i, '---')
        print(b[:1500])
" 2>/dev/null | head -80
