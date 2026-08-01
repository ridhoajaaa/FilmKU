import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/features/movies/presentation/widgets/hidden_stream_capture.dart';

/// Unit tests for the early CDN-block abort in [HiddenStreamCapture].
///
/// On-device evidence (2026-08): when an ISP blocks a stream CDN, the embed
/// player keeps retrying the SAME tokenized URL and every attempt fails with a
/// network-level error (ERR_CONNECTION_REFUSED / ERR_NAME_NOT_RESOLVED) within
/// a few seconds. Instead of burning the full capture budget (30s+) on a
/// provably-dead CDN, [HiddenStreamCapture] aborts the provider early after
/// [HiddenStreamCapture.earlyAbortFailureThreshold] repeated fatal failures on
/// a single non-static, non-ad URL.
///
/// These tests pin down the three guards that keep the abort precise:
///   1. static assets (.js/.css/images/fonts) are never treated as a dead CDN;
///   2. only NETWORK-level errors count (ad/tracker HTTP 404/403 noise doesn't);
///   3. the abort fires only after N failures of the SAME URL.
void main() {
  group('HiddenStreamCapture.isStaticAssetUrl', () {
    test('true for scripts, styles, images, fonts and data files', () {
      expect(
        HiddenStreamCapture.isStaticAssetUrl(
          'https://cdn.example.com/js/player.min.js',
        ),
        isTrue,
      );
      expect(
        HiddenStreamCapture.isStaticAssetUrl(
          'https://cdn.example.com/css/main.css',
        ),
        isTrue,
      );
      expect(
        HiddenStreamCapture.isStaticAssetUrl(
          'https://cdn.example.com/img/logo.png',
        ),
        isTrue,
      );
      expect(
        HiddenStreamCapture.isStaticAssetUrl(
          'https://cdn.example.com/fonts/Inter.woff2',
        ),
        isTrue,
      );
      expect(
        HiddenStreamCapture.isStaticAssetUrl(
          'https://cdn.example.com/config.json',
        ),
        isTrue,
      );
      expect(
        HiddenStreamCapture.isStaticAssetUrl('https://cdn.example.com/app.js'),
        isTrue,
      );
    });

    test('false for media URLs — the thing we actually wait on', () {
      expect(
        HiddenStreamCapture.isStaticAssetUrl(
          'https://cdn.example.com/hls/master.m3u8',
        ),
        isFalse,
      );
      expect(
        HiddenStreamCapture.isStaticAssetUrl(
          'https://cdn.example.com/video/1080p.mp4',
        ),
        isFalse,
      );
      expect(
        HiddenStreamCapture.isStaticAssetUrl(
          'https://4.tu72oelxu6wg3pnjfg.cfd/kfx3p7pvQ56yJYvZO7Xr/VvMrO',
        ),
        isFalse,
      );
    });

    test('ignores query strings and fragments (still static)', () {
      expect(
        HiddenStreamCapture.isStaticAssetUrl(
          'https://cdn.example.com/js/tracker.js?v=123&x=1#frag',
        ),
        isTrue,
      );
    });

    test('is case-insensitive on the extension', () {
      expect(
        HiddenStreamCapture.isStaticAssetUrl(
          'https://cdn.example.com/js/PLAYER.MIN.JS',
        ),
        isTrue,
      );
    });

    test('false for extension-less URLs', () {
      expect(
        HiddenStreamCapture.isStaticAssetUrl('https://cdn.example.com/api/v1'),
        isFalse,
      );
    });
  });

  group('HiddenStreamCapture.isFatalNetworkError', () {
    test('true for network-level failures (blocked/dead CDN signature)', () {
      expect(
        HiddenStreamCapture.isFatalNetworkError('CANNOT_CONNECT_TO_HOST'),
        isTrue,
      );
      expect(
        HiddenStreamCapture.isFatalNetworkError('HOST_LOOKUP'),
        isTrue,
      );
      expect(
        HiddenStreamCapture.isFatalNetworkError('NETWORK_CONNECTION_LOST'),
        isTrue,
      );
      expect(
        HiddenStreamCapture.isFatalNetworkError('CONNECTION_ABORTED'),
        isTrue,
      );
      expect(
        HiddenStreamCapture.isFatalNetworkError('NOT_CONNECTED_TO_INTERNET'),
        isTrue,
      );
      expect(
        HiddenStreamCapture.isFatalNetworkError('FAILED_SSL_HANDSHAKE'),
        isTrue,
      );
    });

    test('false for HTTP/content errors (ad/tracker noise)', () {
      // 404/403 from ad & tracker hosts happen constantly on every ISP and
      // must NEVER abort a provider whose actual player is fine.
      expect(HiddenStreamCapture.isFatalNetworkError('HTTP_ERROR'), isFalse);
      expect(HiddenStreamCapture.isFatalNetworkError('RESOURCE_NOT_FOUND'),
          isFalse);
      expect(
        HiddenStreamCapture.isFatalNetworkError('TIMEOUT'),
        isFalse,
      );
      expect(
        HiddenStreamCapture.isFatalNetworkError(
          'WebResourceErrorType.HTTP_ERROR',
        ),
        isFalse,
      );
    });

    test('false for empty/unknown type names', () {
      expect(HiddenStreamCapture.isFatalNetworkError(''), isFalse);
      expect(HiddenStreamCapture.isFatalNetworkError('UNKNOWN'), isFalse);
    });
  });

  group('HiddenStreamCapture.recordFailure', () {
    test('increments per key, keeping distinct CDN identities separate', () {
      final failures = <String, int>{};
      const urlA = 'https://cdn-a.example.com/stream';
      const urlB = 'https://cdn-b.example.com/stream';

      expect(HiddenStreamCapture.recordFailure(failures, urlA), 1);
      expect(HiddenStreamCapture.recordFailure(failures, urlA), 2);
      expect(HiddenStreamCapture.recordFailure(failures, urlB), 1);
      expect(failures[urlA], 2);
      expect(failures[urlB], 1);
    });
  });

  group('HiddenStreamCapture.cdnFailureKey', () {
    test('strips the query string (rotating signed tokens collapse)', () {
      expect(
        HiddenStreamCapture.cdnFailureKey(
          'https://noir.cdn.store/movie.mp4?sign=abc&t=1785258198',
        ),
        'https://noir.cdn.store/movie.mp4',
      );
    });

    test('strips fragments too', () {
      expect(
        HiddenStreamCapture.cdnFailureKey(
          'https://cdn.example.com/hls/master.m3u8#t=0,60',
        ),
        'https://cdn.example.com/hls/master.m3u8',
      );
    });

    test('two retries with different tokens share one key (the abort can fire)',
        () {
      const retry1 =
          'https://4.tu72oelxu6wg3pnjfg.cfd/kfx3p7pvQ56yJYvZO7Xr/VvMrO'
          '?token=aaa';
      const retry2 =
          'https://4.tu72oelxu6wg3pnjfg.cfd/kfx3p7pvQ56yJYvZO7Xr/VvMrO'
          '?token=bbb';
      final failures = <String, int>{};

      HiddenStreamCapture.recordFailure(
        failures,
        HiddenStreamCapture.cdnFailureKey(retry1),
      );
      final count = HiddenStreamCapture.recordFailure(
        failures,
        HiddenStreamCapture.cdnFailureKey(retry2),
      );

      // Same CDN identity → 2 failures, which is exactly how the dead-CDN
      // abort accumulates despite rotating tokens.
      expect(count, 2);
      expect(HiddenStreamCapture.shouldEarlyAbort(count), isFalse);
    });

    test('keeps different paths on the same host as distinct CDNs', () {
      expect(
        HiddenStreamCapture.cdnFailureKey('https://cdn.example.com/a/v1'),
        isNot(
          HiddenStreamCapture.cdnFailureKey('https://cdn.example.com/b/v2'),
        ),
      );
    });

    test('leaves unparseable strings unchanged', () {
      const weird = 'about:blank';
      expect(HiddenStreamCapture.cdnFailureKey(weird), weird);
    });
  });

  group('HiddenStreamCapture.shouldEarlyAbort', () {
    test('threshold constant is 3 (≈7s of ~3s retries)', () {
      expect(HiddenStreamCapture.earlyAbortFailureThreshold, 3);
    });

    test('false below the threshold, true at/above it', () {
      expect(HiddenStreamCapture.shouldEarlyAbort(0), isFalse);
      expect(HiddenStreamCapture.shouldEarlyAbort(1), isFalse);
      expect(HiddenStreamCapture.shouldEarlyAbort(2), isFalse);
      expect(HiddenStreamCapture.shouldEarlyAbort(3), isTrue);
      expect(HiddenStreamCapture.shouldEarlyAbort(10), isTrue);
    });
  });
}
