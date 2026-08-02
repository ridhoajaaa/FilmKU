import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class FilmKuApp extends StatelessWidget {
  const FilmKuApp({super.key});

  @override
  Widget build(BuildContext context) {
    // iOS gets its own liquid-glass theme; every other platform keeps the
    // classic dark UI. The tab-bar shell is platform-aware too (AppShell).
    final theme = defaultTargetPlatform == TargetPlatform.iOS
        ? AppTheme.ios
        : AppTheme.dark;
    return MaterialApp.router(
      title: 'FilmKU',
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: appRouter,
    );
  }
}
