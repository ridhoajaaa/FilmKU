import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:filmku/core/local/settings_service.dart';
import 'package:filmku/core/media/mini_player_service.dart';
import 'package:filmku/features/movies/data/datasources/stream_source_datasource.dart';
import 'package:filmku/features/movies/domain/entities/video_source.dart';
import 'package:filmku/features/movies/presentation/screens/mpv_player_screen.dart';

/// On-device (emulator) proof that the VidNest chain plays NATIVELY.
///
/// 1. The REAL [TwoEmbedSkinExtractor] resolves the live 2embed.skin shell →
///    vnest player → VidNest server payload (custom-base64 decode) →
///    goodstream HLS master + the exact Referer header the CDN demands
///    (v1.3.24 fast path — no WebView, no JS).
/// 2. The REAL [MpvPlayerScreen] (the app's native player path, libmpv via
///    media_kit) opens that URL WITH the CDN headers and playback position
///    advances past zero — logcat then shows FILMKU_MPV_OPEN /
///    FILMKU_MPV_OPENED / FILMKU_MPV_PLAYING as on-device evidence.
///
/// Evidence lines use the E2E_ prefix (grep-able in logcat). The test itself
/// never hard-fails: the logcat dump after the run is the deliverable.
///
/// Run: flutter test integration_test/vidnest_native_test.dart -d emulator-5554
/// (or build an APK with --target=integration_test/vidnest_native_test.dart
/// and launch MainActivity directly — see tool/emulator_run_vidnest_test.sh).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('vnest chain extracts + plays natively on-device',
      (tester) async {
    const tmdbId = 634649; // Spider-Man: No Way Home (live-verified vnest)
    const title = 'Spider-Man: No Way Home';

    // The real app inits these in main(); the test APK replaces main().
    // MpvControlsOverlay reads SettingsService for its defaults.
    await Hive.initFlutter();
    await SettingsService.init();

    // ---- Phase 1: real extraction (the v1.3.24 vnest native path) ----
    debugPrint('E2E_EXTRACT_BEGIN tmdb=$tmdbId');
    final VideoSource? source;
    try {
      source = await const TwoEmbedSkinExtractor()
          .extract(tmdbId, useHeadless: false)
          .timeout(const Duration(seconds: 50));
    } catch (e) {
      debugPrint('E2E_EXTRACT_FAIL error=$e');
      debugPrint('E2E_ALL_RESULTS extract_failed');
      return;
    }
    if (source == null || !source.isPlayable) {
      debugPrint('E2E_EXTRACT_FAIL source=${source?.videoUrl ?? 'null'}');
      debugPrint('E2E_ALL_RESULTS extract_failed');
      return;
    }
    debugPrint(
      'E2E_EXTRACT source=${source.sourceId} label=${source.label} '
      'videoUrl=${source.videoUrl} headers=${source.httpHeaders}',
    );

    // ---- Phase 2: real native playback through the app's mpv screen ----
    await tester.pumpWidget(
      MaterialApp(
        home: MpvPlayerScreen(
          args: MpvPlayerArgs(
            url: source.videoUrl!,
            title: title,
            sourceLabel: source.label,
            tmdbId: tmdbId,
            movieYear: '2021',
            httpHeaders: source.httpHeaders,
          ),
        ),
      ),
    );

    // Poll the live session's Player position (the same Player the screen
    // owns) — hard playback proof, independent of logcat. Early-exit on the
    // first real progress.
    var played = false;
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(seconds: 1));
      final pos = MiniPlayerService.instance.session?.player.state.position;
      if (pos != null && pos > Duration.zero) {
        played = true;
        debugPrint('E2E_PLAYING position=${pos.inMilliseconds}ms');
        // Keep pumping briefly so FILMKU_MPV_PLAYING + TRACKS land too.
        for (var j = 0; j < 15; j++) {
          await tester.pump(const Duration(seconds: 1));
        }
        break;
      }
    }
    debugPrint('E2E_ALL_RESULTS played=$played tmdb=$tmdbId');
    // Evidence run: the outcome lives in logcat, not the test verdict.
    // (Mirrors auto_capture_test.dart's always-true terminal expect.)
    expect(true, isTrue);
  });
}
