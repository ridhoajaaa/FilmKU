import 'package:filmku/features/movies/presentation/screens/mpv_player_screen.dart';
import 'package:filmku/features/movies/presentation/screens/webview_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the 2026-08 iOS/Android fixes:
/// 1. mpv must NOT surface its full-screen "Native playback failed" error UI
///    for transient errors while the video is genuinely playing (the old code
///    showed the error overlay ON TOP of a still-playing movie).
/// 2. The WebView must offer "Tap to play" when the page shows a paused
///    <video> (spinner-forever on iOS) instead of leaving the user stuck.
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

  group('MpvPlayerScreen startup auto-failover', () {
    test('failover notice is brief (not another dead-end wait)', () {
      // The "switching to backup player…" notice must be short — the point is
      // to escape the dead-end mpv loading state fast, then pop into the
      // WebView fallback automatically.
      expect(
        MpvPlayerScreen.failoverNoticeDuration,
        const Duration(milliseconds: 1500),
      );
      expect(
        MpvPlayerScreen.failoverNoticeDuration,
        lessThan(const Duration(seconds: 3)),
      );
    });
  });

  group('WebViewPlayerScreen.shouldShowTapToPlay', () {
    test('paused video + no native stream + not yet tapped => show', () {
      expect(
        WebViewPlayerScreen.shouldShowTapToPlay(
          paused: 1,
          hasNativeStream: false,
          tapAttempted: false,
        ),
        isTrue,
      );
    });

    test('playing video (paused=0) => no tap prompt', () {
      expect(
        WebViewPlayerScreen.shouldShowTapToPlay(
          paused: 0,
          hasNativeStream: false,
          tapAttempted: false,
        ),
        isFalse,
      );
    });

    test('a discovered native stream suppresses the tap prompt', () {
      expect(
        WebViewPlayerScreen.shouldShowTapToPlay(
          paused: 1,
          hasNativeStream: true,
          tapAttempted: false,
        ),
        isFalse,
      );
    });

    test('after the user already tapped once, no re-prompt', () {
      expect(
        WebViewPlayerScreen.shouldShowTapToPlay(
          paused: 1,
          hasNativeStream: false,
          tapAttempted: true,
        ),
        isFalse,
      );
    });
  });
}
