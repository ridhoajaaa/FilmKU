#!/usr/bin/env bash
# resign_ios.sh — re-sign & re-install the FilmKU IPA on your iPhone with a
# free Apple ID, using the Sideloader binary vendored at
# tool/ios-sideloader/sideloader (see tool/ios-sideloader/BUILD.md).
#
# Free-Apple-ID signatures expire after **7 days**. When the app stops
# launching, re-run this script (same command as the first install) — it
# reuses the certificate/key Sideloader created on first install (stored in
# ~/.config/Sideloader/keys/, matched online by public key), re-provisions
# and reinstalls. No revoke needed.
#
# Usage:
#   ./tool/resign_ios.sh <filmku-unsigned.ipa> <APPLE_ID> [PASSWORD] [2FA_CODE]
#
#   - <ipa>      path to the FilmKU-unsigned.ipa (GitHub Actions artifact)
#   - <APPLE_ID> your Apple ID email, e.g. you@icloud.com
#   - [PASSWORD] optional as argument (avoids the prompt); if omitted you are
#                prompted (input hidden)
#   - [2FA_CODE] optional. If your account uses two-factor auth and Apple
#                sends a 6-digit code to your phone, pass it here — or omit
#                it and the script will ask you interactively when the prompt
#                appears (codes expire in ~1-2 min, so only type it when asked)
#
# Prereqs (all on this machine already):
#   - tool/ios-sideloader/sideloader  (built from source; see BUILD.md)
#   - libimobiledevice + ideviceinstaller
#   - tmux (drives the interactive CLI, which needs a TTY for the password)
#   - iPhone connected over USB, "Trust This Computer" accepted
#
# Security: the Apple ID password is ONLY sent to Apple (via Sideloader) and
# is never logged. Prefer an App-Specific Password (appleid.apple.com →
# Sign-In & Security → App-Specific Passwords) so your real password is not
# exposed.
#
# NOTES:
# 1. Buffering fix (2026-08): Sideloader is a D program whose std.stdio
#    FULL-BUFFERS when stdout is not a terminal. The old version piped its
#    output through `| tee log` (stdout = a pipe), so the "Apple ID:" prompt
#    never flushed and wait_for() timed out. It now runs DIRECTLY in the tmux
#    pane (stdout = a pty → line-buffered), and wait_for() polls the pane via
#    `tmux capture-pane` instead of the log.
# 2. Rate-limit/transient retry (2026-08): live testing showed Apple
#    occasionally answers with an immediate `ssl connect failed` right after
#    login (DeveloperSession created OK, then the certificate-generation
#    request dies — a transient rate-limit / flaky provisioning endpoint,
#    NOT a script bug; a plain retry a minute later succeeds). The whole
#    Sideloader run is now retried up to $MAX_ATTEMPTS times with a backoff
#    sleep between attempts, so a flaky Apple answer no longer fails the
#    install.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIDELOADER="${SIDELOADER:-$ROOT/tool/ios-sideloader/sideloader}"
SESSION="filmku_resign"
LOG="/tmp/resign_ios.log"

# Attempts + backoff for transient Apple failures (see note 2 above).
MAX_ATTEMPTS="${FILMKU_RESIGN_MAX_ATTEMPTS:-3}"
BACKOFF_BASE="${FILMKU_RESIGN_BACKOFF:-20}"   # seconds, doubled per retry

# Safety net: never leave a stale tmux session or staging dir behind, even on
# early die().
STAGE_DIR=""
trap 'rm -rf "$STAGE_DIR"; tmux kill-session -t "$SESSION" 2>/dev/null || true' EXIT

die() { echo "ERROR: $*" >&2; exit 1; }

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <filmku-unsigned.ipa> <APPLE_ID> [PASSWORD] [2FA_CODE]" >&2
  exit 1
fi
IPA="$1"
APPLE_ID="$2"
PASSWORD="${3:-}"
TFA_CODE="${4:-}"

[[ -f "$IPA" ]]      || die "IPA not found: $IPA (download the 'filmku-ios-unsigned' GitHub Actions artifact first)"
[[ -x "$SIDELOADER" ]] || die "Sideloader binary not found at $SIDELOADER — see tool/ios-sideloader/BUILD.md"

# Stage the IPA under a UNIQUE per-run basename before handing it to
# Sideloader. Sideloader extracts the app to /tmp/<ipa-basename>; if a file
# or dir with that exact name already exists in /tmp — e.g. the source IPA
# itself when you download it straight to /tmp — its `file.exists(tempPath)`
# returns true and `rmdirRecurse()` hits a regular FILE, crashing with
# `std/file.d: ENOTDIR: <ipa>: Not a directory` (2026-08, root-caused). A
# random basename guarantees the extraction temp dir is always free.
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/filmku-stage.XXXXXX")"
STAGED_IPA="$STAGE_DIR/filmku-$(date +%s)-$$.ipa"
cp "$IPA" "$STAGED_IPA"
command -v tmux >/dev/null 2>&1            || die "tmux is required"
command -v ideviceinstaller >/dev/null 2>&1 || die "ideviceinstaller is required (libimobiledevice)"

echo "=== 1. Check iPhone over USB ==="
UDID="$(idevice_id -l 2>/dev/null | head -1)"
[[ -n "$UDID" ]] || die "No iPhone detected. Connect it over USB and accept 'Trust This Computer'."
echo "Device UDID: $UDID"

if [[ -z "$PASSWORD" ]]; then
  read -r -s -p "Apple ID password (input hidden): " PASSWORD
  echo
fi
[[ -n "$PASSWORD" ]] || die "Empty password."

# pane_text — current visible pane contents (CR normalized, blank lines
# stripped), also appended to $LOG for post-mortem debugging.
pane_text() {
  local text
  text="$(tmux capture-pane -t "$SESSION" -p 2>/dev/null | tr '\r' '\n' | grep -v '^$')"
  if [[ -n "$text" ]]; then
    printf '%s\n' "$text" >> "$LOG"
  fi
  printf '%s' "$text"
}

# wait_for <pattern> <timeout_seconds> — returns 0 once the pattern appears in
# the tmux PANE (not a log), 1 on timeout.
wait_for() {
  local pattern="$1" timeout="$2" i=0
  while (( i < timeout )); do
    if pane_text | grep -qE "$pattern"; then return 0; fi
    sleep 2
    i=$((i + 2))
  done
  return 1
}

# send() types literal text into the tmux pane (no key-sequence
# interpretation, so passwords with backslashes/spaces are sent verbatim).
send() { tmux send-keys -t "$SESSION" -l "$1"; tmux send-keys -t "$SESSION" Enter; }

# run_attempt — one full Sideloader install run inside a fresh tmux pane.
# Returns 0 on completion (100/100 | InstallComplete | Done!), 1 otherwise.
run_attempt() {
  local attempt="$1"
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -f "$LOG"
  echo
  echo "=== 2.${attempt} Re-sign + re-install via Sideloader (attempt $attempt/$MAX_ATTEMPTS) ==="
  echo "This talks to Apple directly and takes 1-3 minutes."

  # Run Sideloader DIRECTLY in the tmux pane — NOT piped through `tee` (see
  # note 1). remain-on-exit keeps the pane alive after Sideloader exits so the
  # final "100/100 | InstallComplete" line is still readable.
  tmux new-session -d -s "$SESSION" "cd '$ROOT' && '$SIDELOADER' install '$STAGED_IPA' -i"
  tmux set-option -t "$SESSION" remain-on-exit on 2>/dev/null || true

  # --- Apple ID + password ---
  if ! wait_for 'Apple ID:' 90; then
    echo "  attempt $attempt: timed out waiting for the Apple ID prompt (see $LOG)"
    return 1
  fi
  send "$APPLE_ID"
  # getpass() prints the "Password:" prompt to /dev/tty (the tmux pane), so we
  # can now wait for it in the pane before typing.
  if ! wait_for 'Password' 30; then
    echo "  attempt $attempt: timed out waiting for the password prompt (see $LOG)"
    return 1
  fi
  send "$PASSWORD"

  # --- 2FA ---
  if wait_for 'code has been sent|please type it here|Enter the 6-digit' 60; then
    echo
    echo "Apple sent a 2FA code to your phone. It expires in ~1-2 minutes."
    if [[ -z "$TFA_CODE" ]]; then
      read -r -p "Enter the 6-digit code now: " TFA_CODE
    fi
    [[ -n "$TFA_CODE" ]] || die "No 2FA code provided."
    send "$TFA_CODE"
    echo "Code submitted — waiting for Apple to accept it..."
  fi

  # --- Completion ---
  if wait_for '100/100|InstallComplete|Done!' 300; then
    return 0
  fi

  echo "  attempt $attempt: install did not finish cleanly."
  echo "  --- last log lines (attempt $attempt) ---"
  tr '\r' '\n' < "$LOG" | grep -viE '% completed' | tail -8
  return 1
}

# --- Attempt loop with backoff ------------------------------------------------
attempt=0
while true; do
  attempt=$((attempt + 1))
  if run_attempt "$attempt"; then
    break
  fi
  if (( attempt >= MAX_ATTEMPTS )); then
    echo
    echo "=== Install failed after $MAX_ATTEMPTS attempts. ==="
    echo "This is usually a transient Apple rate-limit ('ssl connect failed')."
    echo "Wait a couple of minutes and re-run:"
    echo "  $0 \"$IPA\" \"$APPLE_ID\""
    echo "Full log: $LOG"
    exit 1
  fi
  backoff=$(( BACKOFF_BASE * 2 ** (attempt - 1) ))
  echo
  echo "=== Retrying in ${backoff}s (attempt $((attempt + 1))/$MAX_ATTEMPTS) ==="
  sleep "$backoff"
done

# let the process wind down, then clean up
sleep 3
tmux kill-session -t "$SESSION" 2>/dev/null || true

echo
echo "=== 3. Verify install ==="
if ideviceinstaller -l 2>/dev/null | grep -qi 'com.filmku.filmku'; then
  echo "SUCCESS: FilmKU is installed on your iPhone (signature refreshed)."
else
  echo "WARNING: could not confirm the install — check the log above or run: ideviceinstaller -l"
fi
echo
echo "=== Reminder ==="
echo "Free Apple ID signatures expire after 7 days. Re-run this script weekly:"
echo "  $0 \"$IPA\" \"$APPLE_ID\""
