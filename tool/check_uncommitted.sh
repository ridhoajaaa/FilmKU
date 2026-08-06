#!/usr/bin/env bash
cd /home/ridhoajaaa/DataD/FreeBuff/FilmKU || exit 1
echo '=== git status (short) ==='
git status --short | head -30
echo
echo '=== uncommitted diff stat ==='
git diff --stat | tail -20
echo
echo '=== last 8 commits ==='
git log --oneline -8
echo
echo '=== commits touching mpv player/overlay files ==='
git log --oneline -8 -- lib/features/movies/presentation/screens/mpv_player_screen.dart lib/features/movies/presentation/widgets/mpv_controls_overlay.dart
echo
echo '=== v1.3.21 diff (controls pinning commit) on the overlay ==='
git log --oneline --all | grep -i 'v1.3.21' | head -2
