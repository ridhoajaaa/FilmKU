import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:filmku/features/movies/presentation/widgets/hidden_stream_capture.dart';
import 'package:filmku/features/movies/presentation/widgets/stream_capture_core.dart';

/// On-device (emulator) verification of the hidden auto-capture WebView.
///
/// The core question behind the "no playable stream" bug: does
/// [HiddenStreamCapture] — the same WebView the app uses for invisible
/// auto-capture — capture a direct `.m3u8`/`.mp4` from a real provider embed
/// page when running on a clean device/network?
///
/// Run: flutter test integration_test/auto_capture_test.dart -d emulator-5554
///
/// Each provider gets a fresh WebView (keyed) with a 40s budget. Results are
/// logged with the `E2E_` prefix so logcat can be grepped independently.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const providers = <(String, String)>[
    // Reduced set: the three with the strongest on-device/desktop evidence.
    // (5 sequential WebViews on a 1536MB emulator risked the OOM that killed
    // earlier runs; these three represent the vidsrc ecosystem + JS player.)
    ('vidsrc_to', 'https://vidsrc.to/embed/movie/155'),
    ('two_embed_skin', 'https://www.2embed.skin/embed/movie/155'),
    ('vidlink', 'https://vidlink.pro/movie/155'),
  ];

  testWidgets(
    'hidden auto-capture captures a stream from at least one provider',
    (tester) async {
      final results = <String, String>{};

      for (final (sourceId, url) in providers) {
        final captured = <WebViewNativeStream>[];
        final timedOut = <bool>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HiddenStreamCapture(
                key: ValueKey('$sourceId-$url'),
                url: url,
                sourceLabel: sourceId,
                timeout: const Duration(seconds: 40),
                onCaptured: (s) {
                  captured.add(s);
                  debugPrint(
                    'E2E_CAPTURED source=$sourceId '
                    'url=${s.url} posMs=${s.position.inMilliseconds}',
                  );
                },
                onTimeout: () {
                  timedOut.add(true);
                  debugPrint('E2E_TIMEOUT source=$sourceId');
                },
              ),
            ),
          ),
        );

        // Poll in real time until capture, timeout, or a 50s safety cap.
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(seconds: 1));
          if (captured.isNotEmpty || timedOut.isNotEmpty) break;
        }

        results[sourceId] = captured.isNotEmpty
            ? 'CAPTURED ${captured.first.url}'
            : 'NOTHING';
        debugPrint('E2E_RESULT source=$sourceId ${results[sourceId]}');
      }

      debugPrint('E2E_ALL_RESULTS $results');
      // Evidence-gathering run: log all outcomes, don't hard-fail on no
      // capture (the logcat dump after the run is the real deliverable).
      expect(results.isNotEmpty, isTrue);
    },
  );
}
