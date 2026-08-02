#!/usr/bin/env bash
# install_latest_ios.sh — one-command iOS update: fetch the latest FilmKU IPA
# from the GitHub Release (public repo, no token needed), verify it matches the
# local pubspec version, then re-sign + install it on the connected iPhone.
#
# Usage:
#   ./tool/install_latest_ios.sh <APPLE_ID> [PASSWORD] [2FA_CODE]
#
#   <APPLE_ID>  your Apple ID email (same account the app was first signed with,
#               so the cached certificate in ~/.config/Sideloader/keys/ is reused)
#   [PASSWORD]  optional as argument (avoid in shell history); if omitted,
#               resign_ios.sh prompts hidden
#   [2FA_CODE]  optional; pass it when Apple asks for a 6-digit code
#
# Env overrides:
#   FILMKU_OWNER  GitHub repo owner (default: ridhoajaaa)
#   FILMKU_REPO   GitHub repo name (default: FilmKU)
#   FILMKU_IPA    local IPA filename to use instead of downloading
#   FILMKU_KEEP_IPA  if set, keep the downloaded IPA in the current directory
#
# Requires: curl, unzip, python3, idevice_id, and tool/resign_ios.sh + the
# vendored Sideloader binary (tool/ios-sideloader/sideloader).

set -euo pipefail

OWNER="${FILMKU_OWNER:-ridhoajaaa}"
REPO="${FILMKU_REPO:-FilmKU}"
API="https://api.github.com/repos/$OWNER/$REPO"
DEFAULT_IPA="FilmKU-unsigned.ipa"

die() { echo "ERROR: $*" >&2; exit 1; }

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <APPLE_ID> [PASSWORD] [2FA_CODE]" >&2
  exit 1
fi
APPLE_ID="$1"
PASSWORD="${2:-}"
TFA_CODE="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESIGN="$SCRIPT_DIR/resign_ios.sh"
[[ -f "$RESIGN" ]] || die "resign_ios.sh not found next to this script: $RESIGN"
# Repo root (one level above tool/) — version check must work from any CWD.
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== 1. Find latest release IPA ===="
IPA="${FILMKU_IPA:-}"
if [[ -z "$IPA" ]]; then
  JSON=$(curl -sS --max-time 30 "$API/releases/latest") || die "GitHub API unreachable"
  URL=$(python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    sys.exit('not json')
assets=[a for a in d.get('assets',[]) if a.get('name','').endswith('.ipa')]
if not assets:
    sys.exit('no .ipa asset in latest release')
print(assets[0]['browser_download_url'])
" <<<"$JSON") || die "Could not find the IPA asset in the latest release: $URL"
  IPA="$DEFAULT_IPA"
  echo "  download: $URL"
  curl -sSL --max-time 300 -o "$IPA" "$URL" || die "IPA download failed"
  echo "  saved: $(ls -la "$IPA" | awk '{print $5, $9}')"
else
  [[ -f "$IPA" ]] || die "FILMKU_IPA not found: $IPA"
  echo "  using local: $IPA"
fi

echo
echo "=== 2. Verify version matches pubspec ==="
PLIST=$(unzip -p "$IPA" Payload/Runner.app/Info.plist 2>/dev/null | \
  python3 -c "
import plistlib,sys
try:
    d=plistlib.loads(sys.stdin.buffer.read())
    print(d.get('CFBundleShortVersionString','?'))
except Exception:
    print('?')
" 2>/dev/null || echo '?')
PUB=$(grep -m1 '^version:' "$REPO_ROOT/pubspec.yaml" | awk '{print $2}' | cut -d+ -f1)
echo "  IPA CFBundleShortVersionString : $PLIST"
echo "  pubspec version                : $PUB"
if [[ "$PLIST" != "$PUB" ]]; then
  echo "  WARNING: versions differ — installing anyway (you may be testing an older release)."
fi

echo
echo "=== 3. Re-sign + install ==="
if [[ -n "$PASSWORD" && -n "$TFA_CODE" ]]; then
  "$RESIGN" "$IPA" "$APPLE_ID" "$PASSWORD" "$TFA_CODE"
elif [[ -n "$PASSWORD" ]]; then
  "$RESIGN" "$IPA" "$APPLE_ID" "$PASSWORD"
else
  "$RESIGN" "$IPA" "$APPLE_ID"
fi

echo
echo "=== 4. Cleanup ==="
if [[ -z "${FILMKU_KEEP_IPA:-}" && -z "${FILMKU_IPA:-}" ]]; then
  rm -f "$IPA"
  echo "  removed $IPA (set FILMKU_KEEP_IPA=1 to keep)"
fi
echo "DONE — FilmKU updated on your iPhone."
