import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:filmku/features/movies/presentation/screens/app_shell.dart';

/// Widget tests for the platform-aware [AppShell].
///
/// On iOS the shell must render the floating "liquid glass" capsule tab bar
/// (Home / Search / Favorite / Settings) and NOT the classic Material bottom
/// navigation; every other platform keeps the classic bar (which still labels
/// the third tab "Watchlist").
///
/// NOTE on the platform override: this Flutter version runs the framework's
/// `debugAssertAllFoundationVarsUnset` invariant check BEFORE `addTearDown`
/// callbacks, so `debugDefaultTargetPlatformOverride` must be reset inside a
/// try/finally that completes before the test body returns (an `addTearDown`
/// reset would leave the override set when the check runs and fail every
/// test with "The value of a foundation debug variable was changed by the
/// test").
void main() {
  /// Builds a router with a single-branch StatefulShellRoute so [AppShell]
  /// receives a real [StatefulNavigationShell] (what it needs to render).
  GoRouter buildRouter() => GoRouter(
        initialLocation: '/home',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                AppShell(navigationShell: navigationShell),
            branches: [
              for (final path in [
                '/home',
                '/search',
                '/watchlist',
                '/settings',
              ])
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: path,
                      builder: (context, state) =>
                          Scaffold(body: Center(child: Text(path))),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );

  /// Runs [body] with [debugDefaultTargetPlatformOverride] set to [platform],
  /// guaranteeing the override is cleared (try/finally) before the test body
  /// returns — the framework's foundation-debug invariant check runs before
  /// addTearDown callbacks in this Flutter version.
  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> pumpShell(WidgetTester tester) async {
    final router = buildRouter();
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('iOS: renders the floating glass capsule with 4 iOS tabs',
      (tester) async {
    await withPlatform(TargetPlatform.iOS, () async {
      await pumpShell(tester);

      // iOS tab labels (Instagram-style): Home, Search, Favorite, Settings.
      // GlassTabBar renders each label twice (selected + unselected variants)
      // so use findsWidgets, not findsOneWidget.
      expect(find.text('Home'), findsWidgets);
      expect(find.text('Search'), findsWidgets);
      expect(find.text('Favorite'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);
      // The Android label must NOT leak into the iOS bar.
      expect(find.text('Watchlist'), findsNothing);
      // The classic Material bar must not be present.
      expect(find.byType(BottomNavigationBar), findsNothing);
      // The REAL liquid-glass tab bar (shader-based, iOS 26) floats above.
      expect(find.byType(GlassTabBar), findsOneWidget);
    });
  });

  testWidgets('Android: keeps the classic Material bottom navigation',
      (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      await pumpShell(tester);

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Watchlist'), findsOneWidget);
      expect(find.text('Favorite'), findsNothing);
    });
  });

  testWidgets('iOS: tapping a tab switches the visible branch', (tester) async {
    await withPlatform(TargetPlatform.iOS, () async {
      await pumpShell(tester);

      await tester.tap(find.text('Search').first);
      await tester.pumpAndSettle();
      // The /search branch body rendered (the branch text appears on screen).
      expect(find.text('/search'), findsOneWidget);
    });
  });
}
