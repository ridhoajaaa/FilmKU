import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/core/webview/capture_webview_settings.dart';

/// Tests for [buildCaptureWebViewSettings].
///
/// On-device evidence (2026-08): iOS ships `useShouldInterceptFetchRequest =
/// false` and `useShouldInterceptAjaxRequest = false` by default (Android
/// defaults them on), which silently disabled the hidden capture on iOS —
/// every provider timed out and the app fell back to the visible WebView. The
/// shared builder must therefore EXPLICITLY enable interception on every
/// platform so both iOS and Android capture streams natively.
void main() {
  group('buildCaptureWebViewSettings', () {
    test('enables all interception callbacks (the iOS fix)', () {
      final settings = buildCaptureWebViewSettings();

      // Without these, iOS hidden capture never sees the .m3u8/.mp4 and
      // falls back to the visible WebView (the reported iOS-only regression).
      expect(settings.useShouldInterceptRequest, isTrue);
      expect(settings.useShouldInterceptFetchRequest, isTrue);
      expect(settings.useShouldInterceptAjaxRequest, isTrue);
    });

    test('keeps JS + autoplay + inline media enabled (player needs them)', () {
      final settings = buildCaptureWebViewSettings();

      expect(settings.javaScriptEnabled, isTrue);
      expect(settings.mediaPlaybackRequiresUserGesture, isFalse);
      expect(settings.allowsInlineMediaPlayback, isTrue);
      expect(settings.javaScriptCanOpenWindowsAutomatically, isTrue);
    });

    test('sends the app mobile Chrome UA (CDNs serve same content)', () {
      final settings = buildCaptureWebViewSettings();

      expect(settings.userAgent, contains('Mozilla/5.0'));
    });

    test('captureEnabled=false disables interception (plain browsing)', () {
      final settings = buildCaptureWebViewSettings(captureEnabled: false);

      expect(settings.useShouldInterceptRequest, isFalse);
      expect(settings.useShouldInterceptFetchRequest, isFalse);
      expect(settings.useShouldInterceptAjaxRequest, isFalse);
    });
  });
}
