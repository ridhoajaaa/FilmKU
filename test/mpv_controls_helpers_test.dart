import 'package:flutter_test/flutter_test.dart';
import 'package:filmku/features/movies/presentation/widgets/mpv_controls_overlay.dart';

void main() {
  group('formatDuration', () {
    test('zero renders as 0:00', () {
      expect(formatDuration(Duration.zero), '0:00');
    });

    test('seconds-only pads to m:ss', () {
      expect(formatDuration(const Duration(seconds: 5)), '0:05');
      expect(formatDuration(const Duration(seconds: 65)), '1:05');
    });

    test('minutes render as m:ss with padded seconds', () {
      expect(formatDuration(const Duration(minutes: 5, seconds: 3)), '5:03');
      expect(formatDuration(const Duration(minutes: 42)), '42:00');
    });

    test('hours render as h:mm:ss with padded minutes', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
      expect(formatDuration(const Duration(hours: 2)), '2:00:00');
    });
  });

  group('clampSeekTarget', () {
    test('forward within range adds the delta', () {
      expect(
        MpvControlsOverlay.clampSeekTarget(
          const Duration(seconds: 60),
          MpvControlsOverlay.seekStep,
          const Duration(minutes: 2),
        ),
        const Duration(seconds: 65),
      );
    });

    test('backward within range subtracts the delta', () {
      expect(
        MpvControlsOverlay.clampSeekTarget(
          const Duration(seconds: 60),
          -MpvControlsOverlay.seekStep,
          const Duration(minutes: 2),
        ),
        const Duration(seconds: 55),
      );
    });

    test('backward clamps at zero, never negative', () {
      expect(
        MpvControlsOverlay.clampSeekTarget(
          const Duration(seconds: 3),
          -MpvControlsOverlay.seekStep,
          const Duration(minutes: 2),
        ),
        Duration.zero,
      );
    });

    test('forward clamps at the duration, never past the end', () {
      expect(
        MpvControlsOverlay.clampSeekTarget(
          const Duration(minutes: 1, seconds: 58),
          MpvControlsOverlay.seekStep,
          const Duration(minutes: 2),
        ),
        const Duration(minutes: 2),
      );
    });

    test('unknown (zero) duration disables the upper clamp', () {
      expect(
        MpvControlsOverlay.clampSeekTarget(
          const Duration(seconds: 90),
          MpvControlsOverlay.seekStep,
          Duration.zero,
        ),
        const Duration(seconds: 95),
      );
    });
  });

  group('double-tap seek zones', () {
    test('gesture step is 10 seconds', () {
      expect(MpvControlsOverlay.gestureSeekStep, const Duration(seconds: 10));
    });

    test('left third of the screen rewinds', () {
      expect(MpvControlsOverlay.seekZoneFor(100, 900), SeekZone.left);
      expect(MpvControlsOverlay.seekZoneFor(299, 900), SeekZone.left);
    });

    test('middle third is a no-op zone', () {
      expect(MpvControlsOverlay.seekZoneFor(450, 900), SeekZone.middle);
      expect(MpvControlsOverlay.seekZoneFor(300, 900), SeekZone.middle);
    });

    test('right third of the screen forwards', () {
      expect(MpvControlsOverlay.seekZoneFor(601, 900), SeekZone.right);
      expect(MpvControlsOverlay.seekZoneFor(800, 900), SeekZone.right);
      expect(MpvControlsOverlay.seekZoneFor(900, 900), SeekZone.right);
    });

    test('degenerate width maps to middle', () {
      expect(MpvControlsOverlay.seekZoneFor(0, 0), SeekZone.middle);
      expect(MpvControlsOverlay.seekZoneFor(5, -1), SeekZone.middle);
    });
  });

  group('settings presets', () {
    test('speed options are ordered and include 1.0x', () {
      const speeds = MpvControlsOverlay.speedOptions;
      expect(speeds, contains(1.0));
      expect(speeds, contains(0.5));
      expect(speeds, contains(2.0));
      // Strictly ascending.
      for (var i = 1; i < speeds.length; i++) {
        expect(speeds[i], greaterThan(speeds[i - 1]));
      }
    });

    test('subtitle size range is sane', () {
      expect(MpvControlsOverlay.minSubtitleSize,
          lessThan(MpvControlsOverlay.maxSubtitleSize));
    });
  });
}
