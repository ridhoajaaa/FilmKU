import 'dart:ui';

import 'package:filmku/features/movies/presentation/widgets/mini_player_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

/// v1.3.17 regression: the mini player position is computed by a PURE
/// function and applied with a DIRECT [Positioned] child of the app-level
/// Stack (the previous `LayoutBuilder`-wrapped [Positioned] is ILLEGAL in
/// Flutter — ParentDataWidget corruption rendered the mini player mid-screen
/// and could cover the whole screen with a blank texture that ate every
/// touch). These tests pin the anchor math.
void main() {
  // MiniPlayerOverlay._width / _height (176 x 99).
  const w = 176.0;
  const h = 99.0;
  const margin = 12.0;
  const bottomGap = 120.0;

  group('MiniPlayerOverlay.computeMiniPlayerPosition', () {
    test('portrait: anchored bottom-right, above the tab bar', () {
      const size = Size(390, 844); // iPhone 14 portrait
      final pos = MiniPlayerOverlay.computeMiniPlayerPosition(
        size: size,
        dragOffset: Offset.zero,
      );
      expect(pos.dx, closeTo(size.width - w - margin, 0.001));
      expect(pos.dy, closeTo(size.height - h - bottomGap, 0.001));
    });

    test('landscape: anchored bottom-right too (follows rotation)', () {
      const size = Size(844, 390); // iPhone 14 landscape
      final pos = MiniPlayerOverlay.computeMiniPlayerPosition(
        size: size,
        dragOffset: Offset.zero,
      );
      expect(pos.dx, closeTo(size.width - w - margin, 0.001));
      expect(pos.dy, closeTo(size.height - h - bottomGap, 0.001));
    });

    test('drag far up-left clamps to the top-left corner', () {
      const size = Size(390, 844);
      final pos = MiniPlayerOverlay.computeMiniPlayerPosition(
        size: size,
        dragOffset: const Offset(-9999, -9999),
      );
      expect(pos.dx, 0);
      expect(pos.dy, 0);
    });

    test('drag far down-right clamps inside the screen', () {
      const size = Size(390, 844);
      final pos = MiniPlayerOverlay.computeMiniPlayerPosition(
        size: size,
        dragOffset: const Offset(9999, 9999),
      );
      expect(pos.dx, closeTo(size.width - w, 0.001));
      expect(pos.dy, closeTo(size.height - h, 0.001));
    });

    test('drag delta is preserved relative to the anchor (inside bounds)', () {
      const size = Size(390, 844);
      // Small offsets that stay inside the clamped bounds (a large +dx would
      // correctly hit the right-edge clamp and no longer equal the delta).
      const drag = Offset(10, -20);
      final anchor =
          Offset(size.width - w - margin, size.height - h - bottomGap);
      final pos = MiniPlayerOverlay.computeMiniPlayerPosition(
        size: size,
        dragOffset: drag,
      );
      expect(pos - anchor, drag);
    });
  });
}
