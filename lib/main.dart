import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/local/settings_service.dart';
import 'features/movies/data/local/watchlist_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local storage must be ready before any provider reads it.
  await Hive.initFlutter();
  await SettingsService.init();
  await WatchlistService.init();

  runApp(const ProviderScope(child: FilmKuApp()));
}
