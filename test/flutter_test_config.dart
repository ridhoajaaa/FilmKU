import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the real Roboto + MaterialIcons fonts from the Flutter SDK cache so
/// widget-test goldens render actual glyphs (instead of the Ahem block font).
///
/// Without this, `matchesGoldenFile` output shows solid rectangles for every
/// Text/Icon — fine for layout, useless for verifying the iOS glass UI.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/flutter';
  final fontsDir = Directory('$flutterRoot/bin/cache/artifacts/material_fonts');

  // Fail-safe: only load when the SDK font cache is actually present (a
  // different machine / CI without FLUTTER_ROOT) — otherwise fall back to
  // Ahem instead of throwing a FileSystemException from EVERY test file.
  if (fontsDir.existsSync() &&
      File('${fontsDir.path}/Roboto-Regular.ttf').existsSync() &&
      File('${fontsDir.path}/MaterialIcons-Regular.otf').existsSync()) {
    Future<ByteData> readFont(String name) async => ByteData.sublistView(
          await File('${fontsDir.path}/$name').readAsBytes(),
        );

    final roboto = FontLoader('Roboto')
      ..addFont(readFont('Roboto-Regular.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(readFont('MaterialIcons-Regular.otf'));

    await Future.wait([roboto.load(), icons.load()]);
  } else {
    // Make the Ahem fallback visible: a dev regenerating goldens without the
    // SDK fonts must know the PNGs will show block glyphs, or they might
    // commit Ahem goldens that break byte-compare for everyone else.
    // stderr.writeln (not print) to satisfy the avoid_print lint.
    stderr.writeln('flutter_test_config: SDK fonts not found at '
        '${fontsDir.path} — goldens will use the Ahem fallback font.');
  }
  await testMain();
}
