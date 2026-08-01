#!/usr/bin/env bash
# sideload_ios.sh — install the FilmKU IPA on your iPhone for FREE using a
# personal Apple ID (no $99 Developer account, no Mac, Linux host).
#
# How it works:
#   AltServer-Linux (NyaMisty) talks to Apple's signing service with your
#   Apple ID, fetches a free development certificate + provisioning profile,
#   re-signs the IPA with its OWN signing implementation, and installs it via
#   libimobiledevice (ideviceinstaller) over USB. One command, end to end —
#   and it is fully re-runnable for the 7-day expiry cycle.
#
#   (zsign is a separate manual re-signer kept in tooling docs as a fallback;
#   this script does not use it.)
#
# Usage:
#   ./tool/sideload_ios.sh <filmku-unsigned.ipa> <APPLE_ID> [APP_SPECIFIC_PASSWORD]
#
#   - <ipa>             path to the IPA file to install. The GitHub Actions
#                       artifact "filmku-ios-unsigned" downloads as a WRAPPER
#                       zip (filmku-ios-unsigned.zip) containing
#                       FilmKU-unsigned.ipa — unzip it first and pass the inner
#                       .ipa, e.g.:
#                         unzip ~/Downloads/filmku-ios-unsigned.zip -d ~/Downloads
#                         ./tool/sideload_ios.sh ~/Downloads/FilmKU-unsigned.ipa \
#                             you@icloud.com
#   - <APPLE_ID>        your Apple ID email, e.g. you@icloud.com
#   - [password]        optional as argument; if omitted, you are prompted
#                       (avoids the password landing in your shell history).
#                       Note: AltServer-Linux only accepts -p as a CLI arg, so
#                       the password is briefly visible in `ps` while it runs.
#
# Security tip: prefer an App-Specific Password
#   appleid.apple.com -> Sign-In & Security -> App-Specific Passwords
#   A token scoped to signing only; revocable; avoids exposing your real
#   iCloud password. The password is ONLY sent to Apple (via AltServer), never
#   to this script or anywhere else.
#
# Prereqs (all already installed on this machine):
#   - libimobiledevice + usbmuxd (pacman)
#   - ideviceinstaller            (AUR)
#   - AltServer-Linux binary      (/tmp/AltServer-x86_64, v0.0.5)
#   - iPhone connected over USB and "Trust This Computer" accepted
#
# If signing fails with a cryptic error, the third-party anisette server may
# be down — override it, e.g.:
#   ALTSERVER_ANISETTE_SERVER=https://some-anisette.example bash tool/sideload_ios.sh ...

set -euo pipefail

ALTSERVER="${ALTSERVER:-/tmp/AltServer-x86_64}"
UPLOADED_UDID="${UPLOADED_UDID:-}"

die() { echo "ERROR: $*" >&2; exit 1; }

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <filmku-unsigned.ipa> <APPLE_ID> [APP_SPECIFIC_PASSWORD]" >&2
  exit 1
fi
IPA="$1"
APPLE_ID="$2"
PASSWORD="${3:-}"

[[ -f "$ALTSERVER" ]] || die "AltServer binary not found at $ALTSERVER (download it from https://github.com/NyaMisty/AltServer-Linux/releases)"
[[ -f "$IPA" ]] || die "IPA not found: $IPA (download the 'filmku-ios-unsigned' artifact from GitHub Actions first)"
[[ -x "$ALTSERVER" ]] || chmod +x "$ALTSERVER"

echo "=== 1. Check iPhone over USB ==="
UDID="${UPLOADED_UDID:-$(idevice_id -l 2>/dev/null | head -1 || true)}"
[[ -n "$UDID" ]] || die "No iPhone detected. Connect it over USB and accept 'Trust This Computer'."
echo "Device UDID: $UDID"

if [[ -z "$PASSWORD" ]]; then
  read -r -s -p "Apple ID password (input hidden): " PASSWORD
  echo
fi
[[ -n "$PASSWORD" ]] || die "Empty password."

echo "=== 2. Sign + install via AltServer-Linux (talks to Apple directly) ==="
echo "This fetches a free dev certificate for your Apple ID, signs FilmKU,"
echo "and installs it. Takes 1-3 minutes."
"$ALTSERVER" -u "$UDID" -a "$APPLE_ID" -p "$PASSWORD" "$IPA"

echo
echo "=== 3. Verify install ==="
if ideviceinstaller -l 2>/dev/null | grep -qi 'com.filmku.filmku'; then
  echo "SUCCESS: FilmKU is installed on your iPhone."
else
  echo "WARNING: install may have failed or the bundle id differs — check the"
  echo "AltServer output above. You can also verify with: ideviceinstaller -l"
fi
echo
echo "=== Reminder: free Apple ID certificates expire after 7 days ==="
echo "When the app stops launching, just re-run this script with the same IPA"
echo "to refresh the signature. (Or use SideStore/AltStore for auto-refresh.)"
