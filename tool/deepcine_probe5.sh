#!/bin/bash
# DeepCine probe 5: backend velvetreel hidup? Jalur API vod di dex?
cd /tmp/deepcine
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'

echo '=== 1. Backend velvetreel.7nkznc.com ==='
curl -s -L --max-time 10 -A "$UA" -o /tmp/dc_velvet.html -w 'HTTP=%{http_code} size=%{size_download} type=%{content_type}\n' 'https://velvetreel.7nkznc.com/' 2>&1
head -c 300 /tmp/dc_velvet.html 2>/dev/null | tr -d '\n'
echo
echo '--- sub-path umum (vod/api/index) ---'
for p in api vod index.php api/vod api/index; do
  code=$(curl -s -L --max-time 8 -A "$UA" -o /tmp/dc_vp.txt -w '%{http_code}' "https://velvetreel.7nkznc.com/$p" 2>/dev/null)
  size=$(wc -c < /tmp/dc_vp.txt 2>/dev/null)
  echo "$p -> HTTP=$code size=$size"
done

echo
echo '=== 2. Jalur API di dex: pola /api/ atau index.php atau ?ac= ==='
strings -n 6 /tmp/all_dex.bin 2>/dev/null | grep -o -E '(/api/[a-z0-9_/]{2,40}|index\.php[^" ]{0,40}|\?ac=[a-z0-9_]{2,20}|\?m=[a-z0-9_-]{2,20}|/vod/[a-z0-9_]{2,20})' | sort -u | head -20

echo
echo '=== 3. Cari "maccms" / "3s" / "ff" vod framework signatures ==='
strings -n 5 /tmp/all_dex.bin 2>/dev/null | grep -iE 'maccms|macCMS|wqVOD|ctVOD|3s.*vod|vodtype|vodclass|playfrom' | sort -u | head -10

echo
echo '=== 4. Cek wsTime value (hex -> date) ==='
python3 -c "print('wsTime=0x6971e822 ->', __import__('datetime').datetime.fromtimestamp(0x6971e822))" 2>/dev/null

echo
echo '=== 5. domain 7nkznc.com / b7m6.com / 386m1.com / e6r4r1.com (group yang sama?) ==='
for d in velvetreel.7nkznc.com velvetreel.b7m6.com fxuo.386m1.com sdgc.e6r4r1.com; do
  ip=$(getent hosts $d 2>/dev/null | awk '{print $1}' | head -1)
  echo "$d -> ${ip:-DNS_FAIL}"
done
