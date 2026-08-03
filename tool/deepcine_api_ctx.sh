#!/usr/bin/env bash
# Find how DeepCine builds its VelvetReel API requests.
set -u
DEX=/tmp/all_dex.bin

echo "=== A. 'velvetreel' + '7nkznc' + 'b7m6' occurrences ==="
strings "$DEX" | grep -iE 'velvetreel|7nkznc|b7m6|g8w6|e6r4r1' | sort -u | head -20

echo
echo "=== B. 'error1' + companion strings ==="
strings "$DEX" | grep -iE 'error1|error2|error3|errno|result_code|code.?[:=]' | grep -ivE 'Rerror|ERROR_|errorCode[^a-z]|errno\(' | sort -u | head -20

echo
echo "=== C. Strings near api paths (URL templates) ==="
strings "$DEX" | grep -oE '[a-zA-Z0-9_/.{}-]{4,60}(movie|stream|play|detail|search|source|video|media|get)[a-zA-Z0-9_/.{}-]*' | sort -u | head -40

echo
echo "=== D. token/auth/device-id param names ==="
strings "$DEX" | grep -iE '(token|sign|nonce|device_id|deviceId|uuid|fingerprint|ver|version|appid|app_id|timestamp|ts=|client|appkey|app_key|secret|md5|sha1|hmac)' | sort -u | head -40

echo
echo "=== E. host_list / multi-host logic (these backends rotate domains) ==="
strings "$DEX" | grep -iE 'host_list|hostList|domain|baseHost|apiHost|spHost|cdnDomain|domainList' | sort -u | head -25

echo
echo "=== F. ExoPlayer usage hints (custom headers / UA) ==="
strings "$DEX" | grep -iE 'setRequestHeaders|DefaultHttpDataSource|httpHeaders|Referer|User-Agent|setUserAgent' | sort -u | head -15
