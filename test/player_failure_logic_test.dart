import 'package:filmku/features/movies/presentation/screens/mpv_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the 2026-08 iOS/Android fixes:
/// 1. mpv must NOT surface its full-screen "Native playback failed" error UI
///    for transient errors while the video is genuinely playing (the old code
///    showed the error overlay ON TOP of a still-playing movie).
/// 2. A never-started stream auto-fails-over to the backup path instead of
///    parking the full error UI over a still-loading player.
void main() {
  group('MpvPlayerScreen.shouldSurfaceFailure', () {
    test('surfaces failure when playback never started', () {
      expect(
        MpvPlayerScreen.shouldSurfaceFailure(
          sawPlaying: false,
          lastPosition: Duration.zero,
        ),
        isTrue,
      );
    });

    test('ignores transient error while playing (video progresses)', () {
      expect(
        MpvPlayerScreen.shouldSurfaceFailure(
          sawPlaying: true,
          lastPosition: const Duration(seconds: 30),
        ),
        isFalse,
      );
    });

    test('ignores error right after playing=true even at position zero', () {
      // playing=true alone means the stream started — an immediate error
      // (e.g. a dropped segment on open) must not cover the player.
      expect(
        MpvPlayerScreen.shouldSurfaceFailure(
          sawPlaying: true,
          lastPosition: Duration.zero,
        ),
        isFalse,
      );
    });

    test('ignores transient error when position advanced (seek proof)', () {
      // A successful seek to the handoff position reports position > 0 even
      // before the first playing=true event — that's evidence the stream
      // loads, so a transient error must not surface the failure UI.
      expect(
        MpvPlayerScreen.shouldSurfaceFailure(
          sawPlaying: false,
          lastPosition: const Duration(seconds: 5),
        ),
        isFalse,
      );
    });

    test('surfaces failure only with NO evidence of playback', () {
      expect(
        MpvPlayerScreen.shouldSurfaceFailure(
          sawPlaying: false,
          lastPosition: Duration.zero,
        ),
        isTrue,
      );
    });
  });

  group('MpvPlayerScreen.shouldSurfaceSilentFreeze', () {
    test('surfaces failure when playing but position froze (silent CDN kill)',
        () {
      expect(
        MpvPlayerScreen.shouldSurfaceSilentFreeze(
          playing: true,
          sawPlaying: true,
          currentPosition: const Duration(seconds: 120),
          lastWatchPosition: const Duration(seconds: 120),
        ),
        isTrue,
      );
    });

    test('no surface when position keeps advancing', () {
      expect(
        MpvPlayerScreen.shouldSurfaceSilentFreeze(
          playing: true,
          sawPlaying: true,
          currentPosition: const Duration(seconds: 150),
          lastWatchPosition: const Duration(seconds: 120),
        ),
        isFalse,
      );
    });

    test('no false stall after a backward seek (raw position, not watermark)',
        () {
      // User seeks back to rewatch a scene: raw position drops below the
      // previous tick's value, but the watchdog compares RAW per-tick values
      // so a still-playing stream must NOT be flagged as stalled.
      expect(
        MpvPlayerScreen.shouldSurfaceSilentFreeze(
          playing: true,
          sawPlaying: true,
          currentPosition: const Duration(seconds: 30),
          lastWatchPosition: const Duration(seconds: 120),
        ),
        isFalse,
      );
    });

    test('no surface when user paused (playing=false)', () {
      expect(
        MpvPlayerScreen.shouldSurfaceSilentFreeze(
          playing: false,
          sawPlaying: true,
          currentPosition: const Duration(seconds: 120),
          lastWatchPosition: const Duration(seconds: 120),
        ),
        isFalse,
      );
    });

    test('no surface before playback ever started', () {
      expect(
        MpvPlayerScreen.shouldSurfaceSilentFreeze(
          playing: false,
          sawPlaying: false,
          currentPosition: Duration.zero,
          lastWatchPosition: Duration.zero,
        ),
        isFalse,
      );
    });
  });

  group('MpvPlayerScreen.shouldAutoFailoverOnStall', () {
    test('zero progress => never-started => auto-failover (not full error UI)',
        () {
      // libmpv can report `playing` while STILL LOADING, so an error with no
      // position progress means the CDN rejected the stream before the first
      // frame (vidlink signed URLs → 403/428). Must NOT park the full
      // "Native playback failed" UI over a still-loading player.
      expect(
        MpvPlayerScreen.shouldAutoFailoverOnStall(
          lastPosition: Duration.zero,
        ),
        isTrue,
      );
    });

    test('real progress happened => genuine stall => keep full error UI', () {
      expect(
        MpvPlayerScreen.shouldAutoFailoverOnStall(
          lastPosition: const Duration(seconds: 42),
        ),
        isFalse,
      );
    });
  });

  group('MpvPlayerScreen startup auto-failover', () {
    test('failover notice is brief (not another dead-end wait)', () {
      // The "switching to backup player…" notice must be short — the point is
      // to escape the dead-end mpv loading state fast, then pop into the
      // WebView fallback automatically. 2.5s balances readability of the
      // real CDN error shown underneath against speed of escape.
      expect(
        MpvPlayerScreen.failoverNoticeDuration,
        const Duration(milliseconds: 2500),
      );
      expect(
        MpvPlayerScreen.failoverNoticeDuration,
        lessThan(const Duration(seconds: 4)),
      );
    });
  });
}
