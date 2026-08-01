#!/usr/bin/env bash
# One script for the build → install → verify loop used during on-device
# stream debugging.
#
# Replaces the ad-hoc scripts: build_install_autocapture.sh,
# verify_autocapture_apk.sh, final_build_verify.sh, final_verify2.sh
# (and the redundant build_install_v3.sh).
#
# Usage:
#   ./tool/build_verify.sh                build + install + verify (default)
#   ./tool/build_verify.sh --verify-only  verify the existing APK only
#   ./tool/build_verify.sh --help         show this usage
#
# Notes:
# - No `set -e`: zero-count greps in the verify step must not abort the run.
# - The non-ASCII UI string is extracted as UTF-16 (`strings -e S`) and
#   nulls stripped, because Dart stores literals containing non-ASCII chars
#   as UTF-16 in the AOT snapshot (plain `strings` misses them).

export PATH="/home/ridhoajaaa/flutter/bin:$PATH"
export ANDROID_HOME=/opt/android-sdk
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
SO=lib/arm64-v8a/libapp.so
PKG=com.filmku.filmku

# Diagnostic strings compiled into libapp.so — add new FILMKU_* logs here.
DIAG_STRINGS=(
  'FILMKU_AUTOCAPTURE_BEGIN'
  'FILMKU_AUTOCAPTURE_TRUNCATE'
  'FILMKU_AUTOCAPTURE_OPEN'
  'FILMKU_AUTOCAPTURE_USERSCRIPT_ADDED'
  'FILMKU_AUTOCAPTURE_LOADSTART'
  'FILMKU_AUTOCAPTURE_LOADSTOP'
  'FILMKU_AUTOCAPTURE_RECVERROR'
  'FILMKU_AUTOCAPTURE_CDN_FAIL'
  'FILMKU_AUTOCAPTURE_EARLY_ABORT'
  'FILMKU_AUTOCAPTURE_ADBLOCK'
  'FILMKU_AUTOCAPTURE_CAPTURED'
  'FILMKU_AUTOCAPTURE_TIMEOUT'
  'FILMKU_AUTOCAPTURE_TIMEOUT retry'
  'FILMKU_AUTOCAPTURE_OK'
  'HiddenStreamCapture'
  'embedIsMediaUrl'
  'all providers exhausted'
  'FILMKU_WEBVIEW_NATIVE_READY'
  'FILMKU_WEBVIEW_HANDOFF'
  'FILMKU_WEBVIEW_BLANK'
  'FILMKU_WEBVIEW_BLANK_FAILOVER'
  'FILMKU_MPV_OPEN'
  'FILMKU_MPV_OPENED'
  'FILMKU_MPV_FAILED_RETURN_WEBVIEW'
  'advanceStableProbe'
  'autoHandoff'
  'autoHandoffCountdownSeconds'
)

usage() {
  sed -n '2,19p' "${BASH_SOURCE[0]}"
  exit 0
}

[ "${1:-}" = '--help' ] && usage
if [ "${1:-}" = '--verify-only' ]; then
  VERIFY_ONLY=1
else
  VERIFY_ONLY=0
fi

if [ "$VERIFY_ONLY" -eq 0 ]; then
  echo '=== 1. BUILD APK RELEASE ==='
  flutter build apk --release 2>&1 | tail -3
  ls -la "$APK"
  echo
  echo '=== 2. INSTALL ==='
  adb install -r "$APK" 2>&1 | tail -2
  echo
  echo '=== 3. CLEAR LOGCAT ==='
  adb logcat -c
  echo 'LOGCAT_CLEARED'
  echo
else
  echo '=== VERIFY ONLY (skipping build/install) ==='
  echo
fi

echo '=== 4. BINARY VERIFY ==='
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -o -q "$APK" "$SO" -d "$WORK"
LIBSO="$WORK/$SO"

echo '--- diagnostic strings ---'
for s in "${DIAG_STRINGS[@]}"; do
  echo -n "$s: "
  strings "$LIBSO" | grep -c "$s" || true
done

echo '--- non-ASCII UI string (UTF-16, nulls stripped) ---'
echo -n 'Mencari stream tanpa iklan: '
strings -e S "$LIBSO" | tr -d '\000' | grep -c 'Mencari stream tanpa iklan' || true
echo -n 'Pindah ke player native: '
strings -e S "$LIBSO" | tr -d '\000' | grep -c 'Pindah ke player native' || true

echo '--- signature ---'
/opt/android-sdk/build-tools/36.0.0/apksigner verify --print-certs "$APK" 2>/dev/null | grep -i 'DN:' || true

echo '--- device last update ---'
adb shell dumpsys package "$PKG" 2>/dev/null | grep -i lastUpdateTime || true

echo
echo 'DONE. Next: adb logcat -d | grep FILMKU_AUTOCAPTURE for the on-device trace.'
