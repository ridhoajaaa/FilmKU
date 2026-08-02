import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:filmku/app.dart';
import 'package:filmku/core/local/settings_service.dart';
import 'package:filmku/features/movies/data/local/watchlist_service.dart';
import 'package:filmku/features/movies/presentation/screens/settings_screen.dart';

/// Regression guard for the 2026-08 user report "Settings can't be opened on
/// iOS": boots the REAL app router with real services on the iOS platform and
/// taps the Settings tab, asserting the Settings screen actually renders.
/// (A hand-rolled diagnostic test proved navigation works; this keeps that
/// proof as a permanent guard.)
void main() {
  late Directory tmpDir;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('filmku_hive_settings');
    Hive.init(tmpDir.path);
    await SettingsService.init();
    await WatchlistService.init();
  });

  tearDownAll(() async {
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {
      // best-effort cleanup
    }
  });

  Future<void> pumpRealApp(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        const ProviderScope(
          child: FilmKuApp(),
        ),
      );
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('iOS: tapping the Settings tab opens the Settings screen',
      (tester) async {
    await pumpRealApp(tester);

    // The glass tab bar labels the 4th tab "Settings" (rendered twice:
    // selected + unselected variants).
    expect(find.text('Settings'), findsWidgets);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    // The real SettingsScreen rendered with its sections.
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('TMDB API'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
  });
}
