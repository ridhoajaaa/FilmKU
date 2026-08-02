import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/features/movies/presentation/screens/player_screen.dart';

/// Unit tests for [PlayerScreen.buildStreamHeaders] — the HTTP headers mpv
/// sends to the stream CDN.
///
/// 2026-08 iOS root cause: mpv opened `Media(url)` with NO headers, so the
/// signed 2embed/vidlink CDN URLs returned 403 on iOS and playback failed
/// with "Native playback failed". The fix mirrors what the in-app WebView
/// sends: `Referer` = the embed page, `Origin` = its scheme://authority, and
/// the app's mobile `User-Agent`.
void main() {
  group('PlayerScreen.buildStreamHeaders', () {
    test('always sends the app mobile User-Agent', () {
      final headers = PlayerScreen.buildStreamHeaders(null);
      expect(headers['User-Agent'], isNotEmpty);
      expect(headers['User-Agent'], contains('Mozilla/5.0'));
    });

    test('adds Referer + Origin when an embed URL is provided', () {
      final headers = PlayerScreen.buildStreamHeaders(
        'https://vidlink.pro/movie/969681?autoplay=1',
      );
      expect(headers['Referer'], 'https://vidlink.pro/movie/969681?autoplay=1');
      expect(headers['Origin'], 'https://vidlink.pro');
    });

    test('omits Referer/Origin for a null or empty embed URL', () {
      expect(PlayerScreen.buildStreamHeaders(null).containsKey('Referer'),
          isFalse);
      expect(
          PlayerScreen.buildStreamHeaders(null).containsKey('Origin'), isFalse);
      expect(
          PlayerScreen.buildStreamHeaders('').containsKey('Referer'), isFalse);
      expect(
          PlayerScreen.buildStreamHeaders('').containsKey('Origin'), isFalse);
    });

    test('never sends a bare Origin when the URL has no authority', () {
      final headers = PlayerScreen.buildStreamHeaders('not-a-url');
      expect(headers.containsKey('Origin'), isFalse);
    });
  });
}
