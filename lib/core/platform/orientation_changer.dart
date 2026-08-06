import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Forces the Android activity into EXPLICIT landscape / restores the default.
///
/// Flutter's `SystemChrome.setPreferredOrientations` maps to Android's
/// *sensor-based* `SCREEN_ORIENTATION_SENSOR_LANDSCAPE`, which MIUI/Xiaomi
/// IGNORES when the system auto-rotate is off (2026-08 on-device: Redmi
/// Note 8 Pro with `accelerometer_rotation=0` kept the whole player in
/// PORTRAIT — the 16:9 video rendered small in the middle of the screen and
/// the bottom control bar never sat at the screen bottom; the classic
/// "controls in the middle" complaint). An EXPLICIT
/// `setRequestedOrientation(SCREEN_ORIENTATION_LANDSCAPE)` — the same call
/// game apps use — is honored regardless of the auto-rotate setting.
/// No-op on non-Android platforms (iOS ignores Android-only orientation
/// policies; the WebView/player screens already handle iOS via
/// `setPreferredOrientations`).
class OrientationChanger {
  OrientationChanger._();

  static const MethodChannel _channel = MethodChannel('filmku/orientation');

  /// Forces the activity into landscape (explicit, non-sensor).
  static Future<void> forceLandscape() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('forceLandscape');
    } catch (_) {
      // Channel missing (tests / unusual embedding) — ignore.
    }
  }

  /// Restores the system default orientation behaviour.
  static Future<void> restore() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('restore');
    } catch (_) {
      // Ignore — same as above.
    }
  }
}
