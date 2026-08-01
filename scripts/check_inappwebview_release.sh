#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# check_inappwebview_release.sh
#
# Monitors pub.dev for a NEWER STABLE release of flutter_inappwebview_android
# than 1.1.3. This project vendors a patched copy of the plugin in
# third_party/ (proguard fix for AGP 9) wired via dependency_overrides —
# see README "Android Build Notes". Once upstream ships a stable fix
# (>= 1.2.0), the vendored override can be removed.
#
# Usage:
#   ./scripts/check_inappwebview_release.sh          # once
#   CURRENT_STABLE=1.0.0 ./scripts/check_inappwebview_release.sh  # simulate alert
#   (cron) 0 9 * * * /path/to/scripts/check_inappwebview_release.sh
#
# Exit codes:
#   0  = latest stable is still the vendored version (nothing to do)
#   2  = a newer STABLE version exists — alert! override can be removed
#   3  = error (network/API/JSON, or a config anomaly like vendored version
#        being newer than anything stable on pub.dev) — check output
# ---------------------------------------------------------------------------

set -u

PACKAGE="flutter_inappwebview_android"
CURRENT_STABLE="${CURRENT_STABLE:-1.1.3}"
API_URL="https://pub.dev/api/packages/$PACKAGE"
TIMEOUT=20

command -v python3 >/dev/null 2>&1 || {
  echo "!! python3 is required (for JSON parsing)"; exit 3; }

# Numeric version comparison: 1.10.2 > 1.9.9 (int parts, not lexical).
version_gt() {
  python3 - "$1" "$2" <<'PY'
import sys
def parts(v):
    return [int(x) for x in v.split('+')[0].split('.')]
a, b = parts(sys.argv[1]), parts(sys.argv[2])
sys.exit(0 if a > b else 1)
PY
}

echo "==> Checking pub.dev for $PACKAGE (current vendored: $CURRENT_STABLE) ..."

TMP="$(mktemp)" || { echo "!! cannot create temp file"; exit 3; }
trap 'rm -f "$TMP"' EXIT

# -w '%{http_code}' catches HTTP errors (429 rate-limit, 404, ...) that a
# valid JSON body would otherwise let slip through silently.
HTTP=$(curl -s --max-time "$TIMEOUT" -w '%{http_code}' -o "$TMP" "$API_URL") || {
  echo "!! curl failed (network/API down?)"; exit 3; }
[ "$HTTP" = "200" ] || {
  echo "!! pub.dev returned HTTP $HTTP"; exit 3; }

python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP" 2>/dev/null || {
  echo "!! Invalid JSON from pub.dev API"; exit 3; }

# Newest STABLE version (excludes pre-releases like 1.2.0-beta.3).
# Reads the saved response from a FILE (not stdin) — a heredoc program
# plus a piped stdin would collide and leave python with empty input.
LATEST_STABLE=$(python3 - "$TMP" "$CURRENT_STABLE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
current = sys.argv[2]
stable = []
for v in data.get('versions', []):
    ver = v['version']
    if '-' not in ver and ver.replace('.', '').replace('+', '').isdigit():
        stable.append(ver)
if not stable:
    print(current)
    sys.exit(0)
def key(v):
    return [int(x) for x in v.split('+')[0].split('.')]
stable.sort(key=key)
print(stable[-1])
PY
)

[ -n "$LATEST_STABLE" ] || {
  echo "!! could not determine latest stable version"; exit 3; }

echo "    Latest stable on pub.dev: $LATEST_STABLE"

# Strip build metadata (+N) before comparing: pub.dev ships rebuilds like
# 1.1.3+1, which must be treated as equal to the vendored 1.1.3, not as a
# downgrade/anomaly.
if [ "${LATEST_STABLE%%+*}" = "${CURRENT_STABLE%%+*}" ]; then
  echo "    No new stable release yet. third_party/ override stays."
  exit 0
fi

if version_gt "$LATEST_STABLE" "$CURRENT_STABLE"; then
  echo ""
  echo "    ============================================================"
  echo "    ALERT: flutter_inappwebview_android $LATEST_STABLE (stable) is out!"
  echo "    The proguard fix is likely upstream now. You can:"
  echo "      1. Remove the dependency_overrides + third_party/ dir"
  echo "      2. flutter pub get && flutter build apk --release"
  echo "      3. Verify AGP 9 builds clean, then delete the README note."
  echo "    ============================================================"
  exit 2
fi

# Shouldn't happen: if the vendored version is NEWER than the latest stable
# on pub.dev, that's a configuration anomaly — be loud, don't look like a
# healthy no-op day.
echo "!! vendored version $CURRENT_STABLE is newer than latest stable $LATEST_STABLE"
exit 3
