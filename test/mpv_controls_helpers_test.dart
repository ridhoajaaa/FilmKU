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
