import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// SPIKE: verifies the `liquid_glass_widgets` package can be integrated.
/// Renders GlassTabBar in the Skia test environment and checks it builds
/// without throwing (the package claims Impeller-only LiquidGlass, but the
/// Glass* widgets should fall back gracefully on Skia).
void main() {
  testWidgets('SPIKE: GlassTabBar renders in Skia test env', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: GlassTabBar.bottom(
            tabs: const [
              GlassTab(icon: Icon(Icons.home_outlined), label: 'Home'),
              GlassTab(icon: Icon(Icons.search_rounded), label: 'Search'),
              GlassTab(
                icon: Icon(Icons.favorite_outline_rounded),
                label: 'Fav',
              ),
              GlassTab(
                icon: Icon(Icons.settings_outlined),
                label: 'Settings',
              ),
            ],
            selectedIndex: 0,
            onTabSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // GlassTabBar renders the label twice (selected + unselected variants).
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.byType(GlassTabBar), findsOneWidget);
  });
}
