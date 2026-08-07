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
}
