import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/features/movies/presentation/screens/player_screen.dart';

/// Unit tests for [PlayerScreen.resolveStartPosition] — where a stream handed
/// to the mpv player starts.
///
/// 2026-08 bug: resume only ran on the direct-extraction path. Auto-capture
/// and WebView-handoff streams carry a ZERO position, so replaying a movie
/// from the Home "Lanjutkan menonton" row always restarted from the beginning
/// whenever those paths were used. [PlayerScreen.resolveStartPosition] is the
/// single source of truth: the stream's own position wins; the saved
/// continue-watching position is the fallback.
void main() {
  group('PlayerScreen.resolveStartPosition', () {
    const saved = Duration(minutes: 34, seconds: 12);

    test('stream position wins over the saved position', () {
      final start = PlayerScreen.resolveStartPosition(
        streamPosition: const Duration(minutes: 2, seconds: 5),
        savedPosition: saved,
      );
      expect(start, const Duration(minutes: 2, seconds: 5));
    });

    test('saved position resumes when the stream starts at zero', () {
      final start = PlayerScreen.resolveStartPosition(
        streamPosition: Duration.zero,
        savedPosition: saved,
      );
      expect(start, saved);
    });

    test('starts from zero with no stream position and no saved progress', () {
      final start = PlayerScreen.resolveStartPosition(
        streamPosition: Duration.zero,
        savedPosition: null,
      );
      expect(start, Duration.zero);
    });

    test('starts from zero when neither source has a position', () {
      final start = PlayerScreen.resolveStartPosition(
        streamPosition: Duration.zero,
        savedPosition: Duration.zero,
      );
      expect(start, Duration.zero);
    });

    test('a non-zero stream position is never overridden by a stale save', () {
      final start = PlayerScreen.resolveStartPosition(
        streamPosition: const Duration(hours: 1, minutes: 40),
        savedPosition: saved,
      );
      expect(start, const Duration(hours: 1, minutes: 40));
    });
  });

  group('PlayerScreen.resolveStartPosition (resume requested)', () {
    const saved = Duration(minutes: 34, seconds: 12);

    test('saved position is authoritative over a small auto-capture position',
        () {
      // The hidden auto-capture WebView reports a small NON-zero capture
      // position (it already played 0-30s of the movie while hunting for the
      // stream URL). For a resume play it must NOT reset the resume point to
      // the first seconds (the 2026-08 "Lanjutkan menonton still starts from
      // the beginning" bug) — the saved position wins.
      final start = PlayerScreen.resolveStartPosition(
        streamPosition: const Duration(seconds: 26),
        savedPosition: saved,
        resumeRequested: true,
      );
      expect(start, saved);
    });

    test('resume with a zero saved position falls back to the stream position',
        () {
      final start = PlayerScreen.resolveStartPosition(
        streamPosition: const Duration(seconds: 5),
        savedPosition: Duration.zero,
        resumeRequested: true,
      );
      expect(start, const Duration(seconds: 5));
    });

    test('resume with no saved progress starts from the stream position', () {
      final start = PlayerScreen.resolveStartPosition(
        streamPosition: const Duration(seconds: 10),
        savedPosition: null,
        resumeRequested: true,
      );
      expect(start, const Duration(seconds: 10));
    });

    test('resume with nothing saved anywhere starts from zero', () {
      final start = PlayerScreen.resolveStartPosition(
        streamPosition: Duration.zero,
        savedPosition: null,
        resumeRequested: true,
      );
      expect(start, Duration.zero);
    });
  });
}
