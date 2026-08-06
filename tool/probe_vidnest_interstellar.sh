#!/usr/bin/env bash
# Probe the Interstellar (TMDB 157336) VidNest HLS chain directly.
# The e2e tool timed out fetching the first segment — check whether that was
# transient or the CDN is actually slow/blocking this title.
set -u
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
REF='https://goodstream.cc/embed/U9ad0OE5c13bI65'
MASTER='https://goodstream.cc/pl/U9ad0OE5c13bI65/0-4?e=QiPcqdIOuMhTO3SDeKcRlApEeTaDHnuV'

echo '=== 1. master with Referer ==='
curl -s -m 20 -A "$UA" -e "$REF" "$MASTER" -o /tmp/is_master.txt -w 'HTTP %{http_code} size %{size_download}\n'
head -c 400 /tmp/is_master.txt
echo

echo '=== 2. variant 720 with Referer ==='
VAR='https://goodstream.cc/pl/U9ad0OE5c13bI65/720?s=0&d=1&e=QiPcqdIOuMhTO3SDeKcRlApEeTaDHnuV'
curl -s -m 20 -A "$UA" -e "$REF" "$VAR" -o /tmp/is_var.txt -w 'HTTP %{http_code} size %{size_download}\n'
head -c 400 /tmp/is_var.txt
echo

echo '=== 3. first segment with Referer (timeout was here) ==='
SEG=$(grep -v '^#' /tmp/is_var.txt | head -1)
echo "seg: $SEG"
curl -s -m 30 -A "$UA" -e "$REF" "$SEG" -o /tmp/is_seg.bin -w 'HTTP %{http_code} size %{size_download} type=%{content_type}\n'
xxd /tmp/is_seg.bin 2>/dev/null | head -3
