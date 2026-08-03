#!/usr/bin/env bash
# Hunt for the API request format + signing algorithm.
set -u
DEX=/tmp/all_dex.bin

echo "=== A. wsSecret/wsTime/vod CDN ==="
strings "$DEX" | grep -iE 'wsSecret|wsTime|/vod/|index5|index[0-9]\.m3u8|\.m3u8\?' | sort -u | head -20

echo
echo "=== B. appkey=/sign= templates (URL building) ==="
strings "$DEX" | grep -oE '[a-zA-Z0-9_&=?%{}./:-]{6,120}(appkey|appKey|signature|sign=|app_ver|device_id|SIGNATURE)[a-zA-Z0-9_&=?%{}./:-]{0,80}' | sort -u | head -40

echo
echo "=== C. signature algorithm hints ==="
strings "$DEX" | grep -iE 'MessageDigest|md5|MD5|HmacSHA|SHA-?1|SHA-?256|secretKey|SECRET|salt|privateKey|publicKey' | sort -u | head -25

echo
echo "=== D. API path strings (short) ==="
strings "$DEX" | grep -oE '"/[a-zA-Z0-9_/]{3,40}"' | grep -iE 'movie|stream|play|vod|video|detail|search|source|api|list|info|home|hot' | sort -u | head -40

echo
echo "=== E. json response parsing (stream payload) ==="
strings "$DEX" | grep -oE '"[a-zA-Z_]{2,30}"' | sort | uniq -c | sort -rn | grep -iE 'play|stream|url|vod|m3u8|mp4|quality|server|key|token|sign|time|expire|detail|list' | head -30
