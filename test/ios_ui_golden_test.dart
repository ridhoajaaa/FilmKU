import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:filmku/core/theme/app_theme.dart';
import 'package:filmku/features/movies/presentation/screens/app_shell.dart';

/// Golden + geometry verification of the platform-aware shell at iPhone 14
/// logical size (390×844).
///
/// - iOS golden: liquid-glass capsule tab bar + iOS theme surface.
/// - Android golden: classic Material bottom nav (regression guard).
/// - Geometry test: after scrolling the home list to its bottom, the last
///   row must sit fully ABOVE the floating capsule (110px iOS bottom padding
///   guarantees content is never hidden behind the bar).
///
/// Goldens use real Roboto/MaterialIcons glyphs via test/flutter_test_config.dart.
/// Regenerate with: flutter test --update-goldens test/ios_ui_golden_test.dart
void main() {
  const iosCapsuleKey = Key('ios_glass_tab_bar');
  const lastItemKey = Key('stub_last_item');

  GoRouter buildRouter() => GoRouter(
        initialLocation: '/home',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                AppShell(navigationShell: navigationShell),
            branches: [
              for (final (path, label) in [
                ('/home', 'HOME_BRANCH'),
                ('/search', 'SEARCH_BRANCH'),
                ('/watchlist', 'WATCHLIST_BRANCH'),
                ('/settings', 'SETTINGS_BRANCH'),
              ])
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: path,
                      builder: (context, state) => path == '/home'
                          ? _ScrollableStub(label: label)
                          : Scaffold(body: Center(child: Text(label))),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );

  Future<void> pumpShell(WidgetTester tester, {required bool ios}) async {
    debugDefaultTargetPlatformOverride =
        ios ? TargetPlatform.iOS : TargetPlatform.android;
    try {
      // iPhone 14 logical size.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = buildRouter();
      await tester.pumpWidget(
        MaterialApp.router(
          theme: ios ? AppTheme.ios : AppTheme.dark,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
    } finally {
      // Reset before the test body returns (foundation invariant check runs
      // before addTearDown callbacks in this Flutter version).
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('iOS golden: liquid glass shell renders (390x844)', (tester) async {
    await pumpShell(tester, ios: true);
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/ios_glass_shell.png'),
    );
  });

  testWidgets('Android golden: classic Material shell unchanged (390x844)',
      (tester) async {
    await pumpShell(tester, ios: false);
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/android_classic_shell.png'),
    );
  });

  testWidgets('iOS: floating capsule never covers scrolled content',
      (tester) async {
    await pumpShell(tester, ios: true);

    // Drag far enough that the 40-row list clamps at its absolute bottom.
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();

    final capsule = tester.getRect(find.byKey(iosCapsuleKey));
    final lastItem = tester.getRect(find.byKey(lastItemKey));

    // The last row ends above the capsule's top edge thanks to the iOS-only
    // 110px bottom padding — content is scrollable, not hidden.
    expect(lastItem.bottom, lessThanOrEqualTo(capsule.top));
    // Sanity: the capsule really is floating near the bottom of the screen.
    expect(capsule.top, greaterThan(600));
    expect(capsule.bottom, lessThanOrEqualTo(844));
  });
}

/// A tall scrollable stub with the same iOS bottom-padding contract as the
/// real tab screens (110px clears the floating capsule).
class _ScrollableStub extends StatelessWidget {
  const _ScrollableStub({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    return ListView(
      padding: EdgeInsets.only(bottom: isIos ? 110 : 0),
      children: [
        for (var i = 0; i < 40; i++)
          Container(
            height: 90,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text('$label item $i'),
          ),
        const SizedBox(height: 24),
        const SizedBox(
          height: 1,
          child: SizedBox(key: Key('stub_last_item')),
        ),
      ],
    );
  }
}
