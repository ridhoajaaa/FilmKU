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
# NOTE on the 2026-08-08 buffering fix: Sideloader is a D program whose
# std.stdio FULL-BUFFERS when stdout is not a terminal. The previous version
# piped its output through `| tee log` (stdout = a pipe), so the "Apple ID:"
# prompt never flushed to the log and wait_for() timed out. It now runs
# DIRECTLY in the tmux pane (stdout = a pty → line-buffered), and wait_for()
# polls the pane via `tmux capture-pane` instead of the log.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIDELOADER="${SIDELOADER:-$ROOT/tool/ios-sideloader/sideloader}"
SESSION="filmku_resign"
LOG="/tmp/resign_ios.log"

# Safety net: never leave a stale tmux session behind, even on early die().
trap 'tmux kill-session -t "$SESSION" 2>/dev/null || true' EXIT

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

echo "=== 2. Re-sign + re-install via Sideloader (reuses existing cert) ==="
echo "This talks to Apple directly and takes 1-3 minutes."

tmux kill-session -t "$SESSION" 2>/dev/null || true
rm -f "$LOG"

# Run Sideloader DIRECTLY in the tmux pane — NOT piped through `tee`. A D
# program full-buffers on a pipe, so the interactive prompts would never
# flush to the log and wait_for() below would time out. In a pty the output
# is line-buffered and visible instantly. remain-on-exit keeps the pane alive
# after Sideloader exits so the final "100/100 | InstallComplete" line is
# still readable (with `tmux has-session` gone, wait_for's last-grep below
# would otherwise miss the completion marker).
tmux new-session -d -s "$SESSION" "cd '$ROOT' && '$SIDELOADER' install '$IPA' -i"
tmux set-option -t "$SESSION" remain-on-exit on 2>/dev/null || true

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

# --- Apple ID + password ----------------------------------------------------
wait_for 'Apple ID:' 90 || die "Timed out waiting for the Apple ID prompt (see $LOG)"
send "$APPLE_ID"
# getpass() prints the "Password:" prompt to /dev/tty (the tmux pane), so we
# can now wait for it in the pane before typing.
wait_for 'Password' 30 || die "Timed out waiting for the password prompt (see $LOG)"
send "$PASSWORD"

# --- 2FA ---------------------------------------------------------------------
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

# --- Completion ----------------------------------------------------------------
if ! wait_for '100/100|InstallComplete|Done!' 300; then
  echo
  echo "=== Install did not finish cleanly. Last log lines: ==="
  tr '\r' '\n' < "$LOG" | grep -viE '% completed' | tail -8
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  die "Sideloader did not complete. See $LOG for details."
fi

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
echo "  $0 <$IPA> <$APPLE_ID>"
