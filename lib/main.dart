import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/local/settings_service.dart';
import 'features/movies/data/local/watchlist_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Debug-only preview: render the iOS liquid-glass UI on any platform so it
  // can be eyeballed without an iPhone/simulator (e.g. on Linux desktop):
  //   flutter run -d linux --dart-define=FILMKU_FORCE_IOS_UI=true
  // No-op in profile/release builds (the kDebugMode guard keeps the override
  // from being applied where defaultTargetPlatform is compile-time const).
  const forceIosUi = bool.fromEnvironment('FILMKU_FORCE_IOS_UI');
  if (forceIosUi && kDebugMode) {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  }

  // libmpv (media_kit) must be initialized before any Player is created.
  MediaKit.ensureInitialized();

  // Local storage must be ready before any provider reads it.
  await Hive.initFlutter();
  await SettingsService.init();
  await WatchlistService.init();

  runApp(const ProviderScope(child: FilmKuApp()));
}
