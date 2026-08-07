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
#
# Also keeps the README "Riwayat versi" list in sync: inserts a placeholder
# changelog heading for the new version (if one isn't there yet) and runs
# tool/gen_changelog_toc.py, so the new version shows up in the version TOC
# immediately.
#
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

# 3. README version TOC (tool/gen_changelog_toc.py).
#    The "Riwayat versi" list is generated FROM the changelog headings, so a
#    new version only shows up once its `### `date` — vX.Y.Z: …` heading
#    exists. Insert a placeholder heading for the new version (unless one was
#    already written before bumping) and regenerate the TOC, so v$SHORT lands
#    in the version list immediately. Edit the placeholder before committing.
#    Note: editing the heading TITLE changes its GitHub anchor, so re-run
#    tool/gen_changelog_toc.py after rewriting the title.
README="$ROOT/README.md"
GEN="$ROOT/tool/gen_changelog_toc.py"

if ! command -v python3 >/dev/null 2>&1; then
  echo "WARN: python3 not found — README version TOC NOT refreshed (run tool/gen_changelog_toc.py after writing the changelog)."
elif [[ ! -f "$README" || ! -f "$GEN" ]]; then
  echo "WARN: README.md or tool/gen_changelog_toc.py missing — version TOC NOT refreshed."
else
  # --build keeps the SAME X.Y.Z, so the heading already exists and the
  # dedupe guard below skips insertion — a build bump never creates a new
  # changelog entry. Only --major/--minor/--patch get a placeholder.
  if ! grep -qE "^### .*v${SHORT}:" "$README"; then
    TODAY="$(date +%F)"
    python3 - "$README" "$TODAY" "$SHORT" <<'PY' || echo "WARN: could not insert changelog placeholder."
import sys
path, today, short = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
marker = "## 📝 Changelog\n"
ph = f"### `{today}` — v{short}: (isi changelog di sini)"
if marker not in text:
    print("SKIP: changelog section (## 📝 Changelog) not found in README.md")
elif ph in text:
    print("SKIP: placeholder heading already present.")
else:
    # Keep the blank line after the H2 (file style): marker is
    # '## 📝 Changelog\n', so replacing it with marker+\n+ph+\n yields
    # '## 📝 Changelog\n\n### ph\n' before the existing first entry.
    open(path, "w", encoding="utf-8").write(text.replace(marker, marker + "\n" + ph + "\n", 1))
    print("OK: placeholder changelog entry added — fill it in before committing (then re-run: python3 tool/gen_changelog_toc.py).")
PY
  fi
  if python3 "$GEN"; then
    echo "OK: README version TOC refreshed (gen_changelog_toc.py)."
  else
    echo "WARN: version TOC refresh failed — run: python3 tool/gen_changelog_toc.py"
  fi
fi
