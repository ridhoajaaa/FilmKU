import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for the 2026-08 "controls in the middle" bug.
///
/// The mpv bottom bar is Align(bottomCenter) → Container(width: ∞) → Row with
/// `Expanded(child: Slider(...))`. Because the bar's Align sits in a
/// `StackFit.expand` Stack, its height constraint is LOOSE up to the full
/// window — and `Expanded` lays flex children out with TIGHT height = the
/// Row's maxHeight, so the bare Slider stretched to the whole window height,
/// the Row/Container followed, and the buttons were vertically CENTERED →
/// the control bar rendered mid-screen on-device (Redmi Note 8 Pro).
///
/// The fix bounds the Slider's cross-axis height (`SizedBox(height: 48)`),
/// which must keep the container shrink-wrapped and flush at the bottom.
void main() {
  const bottomKey = ValueKey<String>('bottom_bar');

  Widget buildPlayerStack({bool fixed = true}) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                key: bottomKey,
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                child: Builder(
                  builder: (context) => Row(
                    children: [
                      const Icon(Icons.pause_rounded),
                      Expanded(
                        child: SizedBox(
                          // The fix: bound the cross-axis height. Without it
                          // the Slider (via Expanded) stretches to the whole
                          // window height.
                          height: fixed ? 48 : null,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7,
                              ),
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white30,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: 0,
                              max: 1000,
                              onChanged: (_) {},
                            ),
                          ),
                        ),
                      ),
                      const Text('0:00 / 1:00'),
                      const Icon(Icons.volume_up_rounded),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('bottom bar shrink-wraps and sits at the bottom (fixed)',
      (tester) async {
    await tester.pumpWidget(buildPlayerStack(fixed: true));
    await tester.pump();

    final overlaySize = tester.getSize(find.byType(Stack).first);
    final barBox =
        tester.renderObject<RenderBox>(find.byKey(bottomKey));

    final barBottom =
        barBox.localToGlobal(Offset(0, barBox.size.height)).dy;
    // ignore: avoid_print
    print('FIXED: overlay=$overlaySize bar=${barBox.size} '
        'barBottomY=$barBottom');

    // The bar must hug its content (~48dp slider + padding), not stretch to
    // the full window height.
    expect(
      barBox.size.height,
      lessThan(overlaySize.height / 2),
      reason: 'fixed: bar must shrink-wrap, not stretch full-height',
    );
    // And it must sit flush at the bottom of the window.
    expect(barBottom, closeTo(overlaySize.height, 1));
  });

  testWidgets('UNFIXED structure still demonstrates the bug (guard)',
      (tester) async {
    // Pins the ORIGINAL bug: without the height bound the bar stretches to
    // the full window height (the mid-screen controls). If this starts
    // behaving like the fixed version, the guard is stale — remove it.
    await tester.pumpWidget(buildPlayerStack(fixed: false));
    await tester.pump();
    final overlaySize = tester.getSize(find.byType(Stack).first);
    final barBox =
        tester.renderObject<RenderBox>(find.byKey(bottomKey));
    // ignore: avoid_print
    print('UNFIXED: bar=${barBox.size} overlay=$overlaySize');
    expect(
      barBox.size.height,
      closeTo(overlaySize.height, 1),
      reason: 'guard: without the fix the bar must still stretch full-height',
    );
  });
}
