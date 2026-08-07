#!/usr/bin/env bash
# bump_version.sh — bump the FilmKU app version in BOTH places that must stay
# in sync: `version:` in pubspec.yaml and `AppConstants.appVersion` in
# lib/core/constants/app_constants.dart.
#
# Usage:
#   ./tool/bump_version.sh [--major|--minor|--patch|--build]
#
# Default is `--build` (increment the +N build number, keep the X.Y.Z).
#
#   --major   2.0.0+N        (breaking / big update)
#   --minor   1.2.0+N        (new feature — the normal "I shipped something")
#   --patch   1.1.1+N        (bugfix only)
#   --build   1.1.0+3        (same version, new build — e.g. re-sign test)
#
# The build number ALWAYS increments by 1 — it is NEVER reset (2026-08 fix:
# resetting it to +1 on a version bump produced a LOWER Android versionCode
# than the installed build, so `adb install -r` failed with
# INSTALL_FAILED_VERSION_DOWNGRADE and updates needed the -d flag). Android
# versionCode = the +N build number, which must be strictly increasing.
# Prints the new version on success.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC="$ROOT/pubspec.yaml"
CONSTANTS="$ROOT/lib/core/constants/app_constants.dart"

MODE="${1:---build}"
case "$MODE" in
  --major|--minor|--patch|--build) ;;
  *) echo "ERROR: unknown mode '$MODE' (use --major|--minor|--patch|--build)" >&2; exit 1 ;;
esac

[[ -f "$PUBSPEC" ]]    || { echo "ERROR: $PUBSPEC not found" >&2; exit 1; }
[[ -f "$CONSTANTS" ]]  || { echo "ERROR: $CONSTANTS not found" >&2; exit 1; }

# Current version: X.Y.Z+N
CUR="$(grep -E '^version: ' "$PUBSPEC" | head -1 | awk '{print $2}' | tr -d '\r')"
[[ "$CUR" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]] \
  || { echo "ERROR: cannot parse current version '$CUR' from $PUBSPEC" >&2; exit 1; }

MAJ="${BASH_REMATCH[1]}"
MIN="${BASH_REMATCH[2]}"
PAT="${BASH_REMATCH[3]}"
BLD="${BASH_REMATCH[4]}"

case "$MODE" in
  # Build number always increments (never resets — see the header comment).
  --major) MAJ=$((MAJ + 1)); MIN=0; PAT=0; BLD=$((BLD + 1)) ;;
  --minor) MIN=$((MIN + 1)); PAT=0; BLD=$((BLD + 1)) ;;
  --patch) PAT=$((PAT + 1)); BLD=$((BLD + 1)) ;;
  --build) BLD=$((BLD + 1)) ;;
esac

NEW="$MAJ.$MIN.$PAT+$BLD"
SHORT="$MAJ.$MIN.$PAT"

# 1. pubspec.yaml: version: 1.1.0+2  ->  version: 1.2.0+1
sed -i "s/^version: .*/version: $NEW/" "$PUBSPEC"

# 2. AppConstants.appVersion: '1.1.0'  ->  '1.2.0'
sed -i "s/static const String appVersion = '[0-9.]*';/static const String appVersion = '$SHORT';/" "$CONSTANTS"

echo "Bumped: $CUR -> $NEW  (AppConstants.appVersion = $SHORT)"

# Sanity: both files now agree.
grep -q "^version: $NEW$" "$PUBSPEC" \
  || { echo "ERROR: pubspec.yaml not updated as expected" >&2; exit 1; }
grep -q "appVersion = '$SHORT'" "$CONSTANTS" \
  || { echo "ERROR: AppConstants.appVersion not updated as expected" >&2; exit 1; }
echo "OK: pubspec.yaml + AppConstants.appVersion in sync."
