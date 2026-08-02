import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Root shell hosting the bottom-tab screens.
///
/// Platform-aware: iOS renders the floating "liquid glass" capsule tab bar
/// ([_IosGlassTabBar], Instagram-style with Home/Search/Favorite/Settings);
/// every other platform keeps the classic Material [BottomNavigationBar].
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// iOS detection is driven by [defaultTargetPlatform] (not the theme) so
  /// it stays consistent with app.dart's theme selection and is trivially
  /// overridable in widget tests via [debugDefaultTargetPlatformOverride].
  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    if (_isIos) {
      return Scaffold(
        // Content scrolls up to (and under) the floating capsule's shadow —
        // the bar itself floats above with its own safe-area margin.
        extendBody: true,
        body: navigationShell,
        bottomNavigationBar: _IosGlassTabBar(
          currentIndex: navigationShell.currentIndex,
          onTap: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
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

/// The iOS "liquid glass" floating tab bar.
///
/// A frosted-glass capsule floating above the screen bottom (Instagram-style):
/// `BackdropFilter` blurs whatever scrolls underneath, the surface is a
/// low-alpha white with a hairline glass border and a soft outer glow, and the
/// active item sits inside a glowing aqua pill. Tabs: Home, Search, Favorite,
/// Settings.
class _IosGlassTabBar extends StatelessWidget {
  const _IosGlassTabBar({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const Color _glass = Color(0x14141424);
  static const Color _glassBorder = Color(0x40FFFFFF);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          // Test hook: lets widget/golden tests measure the capsule rect so
          // they can assert scrolled content never hides behind the bar.
          key: const Key('ios_glass_tab_bar'),
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: _glass,
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: _glassBorder, width: 0.8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: _GlassTabItem(
                        icon: _items[i].icon,
                        label: _items[i].label,
                        selected: i == currentIndex,
                        onTap: () => onTap(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const List<({IconData icon, String label})> _items = [
    (icon: Icons.home_outlined, label: 'Home'),
    (icon: Icons.search_rounded, label: 'Search'),
    (icon: Icons.favorite_outline_rounded, label: 'Favorite'),
    (icon: Icons.settings_outlined, label: 'Settings'),
  ];
}

class _GlassTabItem extends StatelessWidget {
  const _GlassTabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const Color _active = Color(0xFF4DE1FF);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          // Vertical margin 6 (was 10) + smaller icon/gap: the pill's inner
          // Column must fit 72 - 2*0.8 (capsule border) - 2*margin. Under
          // real (non-Ahem) font metrics the old 10px margin overflowed by
          // ~2.6px (caught by the iOS golden test) — these values give it
          // generous headroom.
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0x334DE1FF),
                      Color(0x207C6BFF),
                    ],
                  )
                : null,
            border: selected
                ? Border.all(color: const Color(0x554DE1FF), width: 0.8)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 21,
                color: selected ? _active : Colors.white54,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : Colors.white54,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
