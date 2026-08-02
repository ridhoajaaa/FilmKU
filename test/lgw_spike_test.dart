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

  testWidgets(
      'SPIKE: GlassContainer/GlassTextField/GlassListTile render on Skia',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SingleChildScrollView(
            child: Column(
              children: [
                // GlassContainer with padding — the base surface used across
                // the iOS screens (header banner, detail sections).
                GlassContainer(
                  padding: EdgeInsets.all(16),
                  child:
                      Text('Container', style: TextStyle(color: Colors.white)),
                ),
                SizedBox(height: 8),
                // GlassTextField — the iOS search bar surface.
                GlassTextField(
                  placeholder: 'Search movies…',
                ),
                SizedBox(height: 8),
                // GlassListTile — the iOS Settings row surface.
                GlassListTile(
                  leading: Icon(Icons.key),
                  title: Text('API Key'),
                  trailing: Icon(Icons.edit, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(GlassContainer), findsOneWidget);
    expect(find.byType(GlassTextField), findsOneWidget);
    expect(find.byType(GlassListTile), findsOneWidget);
    expect(find.text('Container'), findsOneWidget);
    expect(find.text('Search movies…'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
  });
}
