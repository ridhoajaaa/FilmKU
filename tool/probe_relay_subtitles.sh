#!/usr/bin/env bash
# Probe the 2vcdn subtitle path the user's movie (1375646) used:
# master → #EXT-X-MEDIA subtitle URI → fetch → is it valid WebVTT?
UA='Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
MASTER='https://2vcdn.skin/stream/ZUFTR1cnt-2G0tV_Iwyufw/kjhhiuahiuhgihdf/1786071677/73567915/master.m3u8'

echo '=== 1. master ==='
curl -s -m 15 -A "$UA" "$MASTER" -o /tmp/sub_master.m3u8 -w 'HTTP %{http_code} size %{size_download}\n'
head -c 600 /tmp/sub_master.m3u8
echo
echo
echo '=== 2. #EXT-X-MEDIA lines (subtitle tracks) ==='
grep -i 'EXT-X-MEDIA' /tmp/sub_master.m3u8
echo
echo '=== 3. subtitle URI fetch (as relay would) ==='
SUB=$(grep -i 'TYPE=SUBTITLES' /tmp/sub_master.m3u8 | grep -oE 'URI="[^"]*"' | head -1 | sed 's/URI="//;s/"//')
echo "sub uri: $SUB"
if [ -n "$SUB" ]; then
  # resolve relative against master
  case "$SUB" in
    http*) SUBURL="$SUB" ;;
    /*) SUBURL="https://2vcdn.skin$SUB" ;;
    *) SUBURL="https://2vcdn.skin/stream/ZUFTR1cnt-2G0tV_Iwyufw/kjhhiuahiuhgihdf/1786071677/73567915/$SUB" ;;
  esac
  echo "resolved: $SUBURL"
  curl -s -m 15 -A "$UA" "$SUBURL" -o /tmp/sub.vtt -w 'HTTP %{http_code} size %{size_download} type=%{content_type}\n'
  echo '--- head ---'
  head -c 300 /tmp/sub.vtt
  echo
  echo '--- is it WebVTT? ---'
  head -c 12 /tmp/sub.vtt | grep -q 'WEBVTT' && echo 'YES: WEBVTT' || echo 'NO: not WebVTT'
  echo '--- is it PNG-wrapped (first bytes)? ---'
  xxd /tmp/sub.vtt 2>/dev/null | head -1
fi
