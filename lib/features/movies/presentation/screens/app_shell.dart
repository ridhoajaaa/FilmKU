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
          child: navigationShell,
        ),
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
/// A frosted-glass capsule floating above the screen bottom (Instagram-style)
/// that mimics the iOS 26 liquid-glass material:
/// - `BackdropFilter` blurs whatever scrolls underneath, and the shell body
///   behind it is saturation-boosted (see [AppShell._saturationBoost]) so the
///   frosted surface reads vivid, like real liquid glass;
/// - a **specular highlight follows the touch** (radial white sheen at the
///   finger position) — the glossy "light on glass" response of the real
///   material;
/// - a luminous **edge glow** (outer white rim) + a **top rim highlight**
///   line, plus a low-alpha white surface with a hairline glass border;
/// - the active item sits inside a glowing aqua pill.
///
/// Tabs: Home, Search, Favorite, Settings.
class _IosGlassTabBar extends StatefulWidget {
  const _IosGlassTabBar({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  State<_IosGlassTabBar> createState() => _IosGlassTabBarState();
}

class _IosGlassTabBarState extends State<_IosGlassTabBar> {
  /// Where the user's finger is inside the capsule — drives the specular
  /// sheen. Kept off-canvas until the first touch.
  Offset _glow = const Offset(-200, -200);
  bool _glowActive = false;

  static const Color _glass = Color(0x1F141424);
  static const Color _glassBorder = Color(0x66FFFFFF);

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
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Listener(
              // Track the finger to move the specular sheen (liquid glass
              // reflects a moving light source).
              onPointerDown: (e) => setState(() {
                _glow = e.localPosition;
                _glowActive = true;
              }),
              onPointerMove: (e) => setState(() => _glow = e.localPosition),
              onPointerUp: (_) => setState(() => _glowActive = false),
              onPointerCancel: (_) => setState(() => _glowActive = false),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  color: _glass,
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(color: _glassBorder, width: 1),
                  boxShadow: const [
                    // Floating shadow below the capsule.
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                    // Luminous edge glow — the bright rim of real glass.
                    BoxShadow(
                      color: Color(0x2AFFFFFF),
                      blurRadius: 16,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Specular sheen following the touch.
                    if (_glowActive)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _SpecularPainter(center: _glow),
                        ),
                      ),
                    // Top rim highlight — the bright upper edge of the glass.
                    Positioned(
                      top: 0,
                      left: 20,
                      right: 20,
                      child: Container(
                        height: 1,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0x00FFFFFF),
                              Color(0x99FFFFFF),
                              Color(0x00FFFFFF),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < _items.length; i++)
                          Expanded(
                            child: _GlassTabItem(
                              icon: _items[i].icon,
                              label: _items[i].label,
                              selected: i == widget.currentIndex,
                              onTap: () => widget.onTap(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
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

/// Paints a soft radial white highlight at the touch point — the specular
/// "light on glass" that follows the finger, exactly like the liquid-glass
/// material responds to touch.
class _SpecularPainter extends CustomPainter {
  const _SpecularPainter({required this.center});

  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          center.dx / size.width * 2 - 1,
          center.dy / size.height * 2 - 1,
        ),
        radius: 0.8,
        colors: const [Color(0x33FFFFFF), Color(0x00FFFFFF)],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_SpecularPainter oldDelegate) =>
      oldDelegate.center != center;
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
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x334DE1FF),
                      blurRadius: 10,
                      spreadRadius: 0.5,
                    ),
                  ]
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
