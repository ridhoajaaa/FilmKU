import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Root shell hosting the bottom-tab screens.
///
/// Platform-aware: iOS renders the floating "liquid glass" capsule tab bar
/// ([GlassTabBar.bottom], the real shader-based iOS 26 material from the
/// `liquid_glass_widgets` package — Home/Search/Favorite/Settings); every
/// other platform keeps the classic Material [BottomNavigationBar].
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// iOS detection is driven by [defaultTargetPlatform] (not the theme) so
  /// it stays consistent with app.dart's theme selection and is trivially
  /// overridable in widget tests via [debugDefaultTargetPlatformOverride].
  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  /// iOS 26 "Liquid Glass" saturation boost (s = 1.3): content behind the
  /// glass is rendered more vivid/saturated so the frosted panels pick up
  /// rich color instead of muddying it. Applied to the whole shell body on
  /// iOS only — the Android build keeps its classic look untouched.
  static const List<double> _saturationBoost = [
    1.23622,
    -0.21456,
    -0.02166,
    0,
    0,
    -0.06378,
    1.08544,
    -0.02166,
    0,
    0,
    -0.06378,
    -0.21456,
    1.27834,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  @override
  Widget build(BuildContext context) {
    if (_isIos) {
      return Scaffold(
        // Content scrolls up to (and under) the floating capsule's shadow —
        // the bar itself floats above with its own safe-area margin.
        extendBody: true,
        // Saturation boost: the "liquid glass" material in iOS 26 saturates
        // whatever sits behind the frosted panels — apply the same treatment
        // to the whole shell body so the capsule's backdrop blur picks up
        // vivid, saturated color.
        body: ColorFiltered(
          colorFilter: const ColorFilter.matrix(_saturationBoost),
          child: Stack(
            children: [
              navigationShell,
              // Bottom scrim (2026-08): the floating capsule's glass blurs
              // whatever sits behind it — on Home, bright movie posters
              // scrolled under the bar made the capsule look SOLID/opaque
              // (pixel-verified: Home capsule band lum ~79 vs ~38 on
              // Settings), while Settings/Search stayed dark-transparent.
              // Native iOS apps fade the content to dark above the tab bar;
              // the same gradient here guarantees the capsule always reads
              // as transparent liquid glass on EVERY tab.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 170,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // Fade in fast (stops 0.0→0.45) so the whole capsule
                      // band sits on dark, then hold at a moderate 0.75:
                      // the pill's glass keeps sampling a dark backdrop on
                      // EVERY tab (bright posters scrolling under the bar on
                      // Home used to make that capsule read solid/opaque —
                      // pixel-verified band mean ~79 vs ~38 elsewhere). The
                      // fade is invisible above the bar; it only guarantees
                      // the glass reads as uniform transparent liquid glass.
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.45, 1.0],
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                          Colors.black.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: GlassTabBar.bottom(
          // Test hook: lets widget/golden tests measure the capsule rect so
          // they can assert scrolled content never hides behind the bar.
          key: const Key('ios_glass_tab_bar'),
          tabs: const [
            // NOTE: no `activeIcon` on ANY tab. GlassTabBar.bottom renders a
            // selected-variant layer OVER the unselected layer for the tabs
            // adjacent to the indicator — with Home selected that layer draws
            // `home_rounded` on top of `home_outlined` → the Home tab looked
            // visibly DOUBLED. Search (identical glyph both states) looked
            // fine, which is why the doubling was only ever on Home. Reusing
            // the same icon for both states makes the overlap invisible;
            // selection is still shown by the indicator pill + selected
            // color + per-tab glow.
            // NO glowColor on ANY tab (2026-08): the old white glow on the
            // Home tab alone (0x33FFFFFF) was the pixel-verified cause of the
            // "Home capsule looks SOLID/opaque while Settings/Search stay
            // transparent" report — the selected Home tab drew a wide white
            // halo across the capsule (band mean ~103 vs ~36 elsewhere),
            // reading as a non-transparent bar. Dropping it makes the
            // capsule read as uniform transparent liquid glass on every tab;
            // selection stays clear via the indicator pill + label/icon color.
            GlassTab(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
            GlassTab(
              icon: Icon(Icons.search_rounded),
              label: 'Search',
            ),
            // Label + icons UNIFIED with Android (bookmark/Watchlist) so the
            // two platforms read the same (2026-08 user request).
            GlassTab(
              icon: Icon(Icons.bookmark_outline_rounded),
              label: 'Watchlist',
            ),
            GlassTab(
              icon: Icon(Icons.settings_outlined),
              label: 'Settings',
            ),
          ],
          selectedIndex: navigationShell.currentIndex,
          onTabSelected: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          // Neutral graphite accent (NOT the old aqua blue) — matches the
          // iOS theme's neutral accent so the bar reads as part of the app.
          // NOTE: glowColor is per-GlassTab (not a GlassTabBar.bottom param) —
          // the per-tab glow is configured on the GlassTab entries above.
          selectedIconColor: const Color(0xFFE8E8EA),
          selectedLabelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorColor: const Color(0x26E8E8EA),
        ),
      );
    }
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            activeIcon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark_outline),
            activeIcon: Icon(Icons.bookmark),
            label: 'Watchlist',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
