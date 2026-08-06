#!/usr/bin/env bash
# Ground truth display/window orientation from the phone.
export ANDROID_HOME=/opt/android-sdk
export PATH=/opt/android-sdk/platform-tools:$PATH
ADB=adb
SERIAL=${1:-mrdm5povbql7guob}
PKG=com.filmku.filmku

echo '=== display info ==='
timeout 10 $ADB -s "$SERIAL" shell dumpsys display 2>/dev/null | grep -iE 'mCurrentOrientation|rotation|DisplayInfo' | head -8

echo
echo '=== window rotation + app window ==='
timeout 10 $ADB -s "$SERIAL" shell dumpsys window displays 2>/dev/null | grep -iE 'cur=|rot=|init=' | head -6
timeout 10 $ADB -s "$SERIAL" shell dumpsys window windows 2>/dev/null | grep -iE "$PKG|mAttrs.*requestedOrientation|screenOrientation" | head -6

echo
echo '=== is app running? ==='
timeout 10 $ADB -s "$SERIAL" shell pidof $PKG 2>&1 || echo 'NOT RUNNING'
echo
echo '=== top activity ==='
timeout 10 $ADB -s "$SERIAL" shell dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|topResumed' | head -2
