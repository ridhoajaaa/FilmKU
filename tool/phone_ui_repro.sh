#!/usr/bin/env bash
# Reproduce the user's real flow on the phone with the RELEASE app:
# home → hero movie → detail → Play → mpv player. Screenshots at key moments.
export ANDROID_HOME=/opt/android-sdk
export PATH=/opt/android-sdk/platform-tools:$PATH
ADB=adb
SERIAL=${1:-mrdm5povbql7guob}
PKG=com.filmku.filmku
mkdir -p /tmp/repro
rm -f /tmp/repro/*.png

adb() { timeout 30 $ADB -s "$SERIAL" "$@"; }
shot() { adb exec-out screencap -p > "/tmp/repro/$1" 2>/dev/null; echo "$1: $(wc -c < /tmp/repro/$1 2>/dev/null) bytes"; }

echo "### 1. FORCE-STOP + LAUNCH"
adb shell am force-stop $PKG 2>/dev/null
adb logcat -c 2>/dev/null || true
sleep 1
adb shell am start -n $PKG/.MainActivity 2>&1 | head -1
echo 'waiting for app up...'
for i in $(seq 1 15); do
  sleep 2
  adb shell pidof $PKG >/dev/null 2>&1 && { echo "app up at ~$((i*2))s"; break; }
done
sleep 10

echo "### 2. HOME"
shot 1_home.png
MD5_HOME=$(md5sum < /tmp/repro/1_home.png | awk '{print $1}')

echo "### 3. TAP HERO (verify by screenshot diff)"
TAPPED=0
for t in "540 500" "540 650" "540 350"; do
  set -- $t
  adb shell input tap "$1" "$2"
  sleep 7
  shot 2_detail.png
  M=$(md5sum < /tmp/repro/2_detail.png | awk '{print $1}')
  if [ -n "$M" ] && [ "$M" != "$MD5_HOME" ]; then echo "detail reached"; TAPPED=1; break; fi
done
[ "$TAPPED" = "1" ] || { echo "NAV FAILED"; exit 3; }

echo "### 4. TAP PLAY (poll logcat for mpv)"
PLAYED=0
for t in "540 1255" "540 1150" "540 1350"; do
  set -- $t
  adb shell input tap "$1" "$2"
  for w in 1 2 3 4 5 6; do
    sleep 5
    if adb logcat -d 2>/dev/null | grep -q 'FILMKU_MPV_OPEN'; then echo "player reached via tap $1,$2"; PLAYED=1; break 2; fi
  done
done
[ "$PLAYED" = "1" ] || { echo "PLAYER NOT REACHED"; adb logcat -d 2>/dev/null | grep FILMKU_ | tail -20; exit 3; }

echo "### 5. WAIT PLAYING + CAPTURE"
SHOT=0
for i in $(seq 1 12); do
  sleep 4
  if [ "$SHOT" = "0" ] && adb logcat -d 2>/dev/null | grep -q 'FILMKU_MPV_PLAYING'; then
    echo ">> PLAYING at ~$((i*4))s"
    sleep 2
    shot 3_player.png
    shot 4_player2.png
    sleep 2
    shot 5_player3.png
    echo '--- orientation ---'
    adb shell dumpsys display 2>/dev/null | grep -i 'mCurrentOrientation' | head -1
    echo '--- window ---'
    adb shell dumpsys window displays 2>/dev/null | grep -iE 'cur=|init=' | head -2
    SHOT=1
    break
  fi
done
[ "$SHOT" = "1" ] || { echo "NO PLAYING EVIDENCE"; adb logcat -d 2>/dev/null | grep FILMKU_ | tail -30; exit 2; }

echo "### 6. EVIDENCE"
adb logcat -d 2>/dev/null | grep -E 'FILMKU_(EXTRACT_SUMMARY|PLAYER_DIRECT|MPV_OPEN|MPV_TRACKS|MPV_SUBTRACK|MPV_PLAYING|SUBS)' | tail -25
