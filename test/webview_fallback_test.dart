import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/features/movies/domain/entities/video_source.dart';
import 'package:filmku/features/movies/presentation/screens/player_screen.dart';
import 'package:filmku/features/movies/presentation/screens/webview_player_screen.dart';
import 'package:filmku/features/movies/data/datasources/stream_source_datasource.dart';
import 'package:filmku/features/movies/presentation/widgets/error_view.dart';
import 'package:filmku/features/movies/presentation/widgets/hidden_stream_capture.dart';
import 'package:filmku/features/movies/presentation/widgets/stream_capture_core.dart';

/// Tests for the WebView fallback player wiring.
void main() {
  VideoSource source(String id, {String? embedUrl}) => VideoSource(
        sourceId: id,
        label: id,
        videoUrl: 'https://cdn.example.com/$id.mp4',
        embedUrl: embedUrl,
      );

  group('PlayerScreen.selectFallbackSource', () {
    test('prefers the selected source when it has an embedUrl', () {
      final selected = source('vidlink', embedUrl: 'https://vidlink.pro/m/1');
      final others = [source('vidsrc_to', embedUrl: 'https://vidsrc.to/e/1')];

      final result = PlayerScreen.selectFallbackSource(selected, others);

      expect(result, same(selected));
    });

    test(
        'falls back to the first source with an embedUrl when selected '
        'has none', () {
      final selected = source('two_embed'); // no embedUrl
      final withEmbed = source('vidsrc_su', embedUrl: 'https://vidsrc.su/e/1');
      final others = [source('cineby'), withEmbed];

      final result = PlayerScreen.selectFallbackSource(selected, others);

      expect(result, same(withEmbed));
    });

    test('returns null when no source has an embedUrl', () {
      final result = PlayerScreen.selectFallbackSource(
        source('two_embed'),
        [source('cineby'), source('vidsrc_to')],
      );

      expect(result, isNull);
    });

    test('returns null when sources list is empty', () {
      expect(
        PlayerScreen.selectFallbackSource(null, const <VideoSource>[]),
        isNull,
      );
    });
  });

  group('PlayerScreen.buildFallbackWebViewSource', () {
    test('builds a WebView fallback from the first enabled provider', () {
      final result = PlayerScreen.buildFallbackWebViewSource(
        1081003,
        isSourceEnabled: (_) => true,
      );

      expect(result, isNotNull);
      expect(result!.embedUrl, contains('1081003'));
      expect(result.videoUrl, isNull); // not playable natively, only embed
    });

    test('skips disabled providers and picks the first enabled one', () {
      final result = PlayerScreen.buildFallbackWebViewSource(
        155,
        isSourceEnabled: (id) => id != 'vidsrc_to',
      );

      expect(result, isNotNull);
      expect(result!.sourceId, isNot('vidsrc_to'));
      expect(result.embedUrl, contains('155'));
    });

    test('reaches 2Embed.skin when earlier providers are disabled', () {
      // Both legacy 2Embed domains are live 2026-08; when the earlier
      // providers are toggled off, the aggregator must surface the .skin
      // domain's embed URL (verified alive with correct title resolution).
      final result = PlayerScreen.buildFallbackWebViewSource(
        969681,
        isSourceEnabled: (id) => id == 'two_embed_skin' || id == 'vidsrc_su',
      );

      expect(result, isNotNull);
      expect(result!.sourceId, 'two_embed_skin');
      expect(result.embedUrl, 'https://www.2embed.skin/embed/movie/969681');
    });

    test('returns null when every provider is disabled', () {
      final result = PlayerScreen.buildFallbackWebViewSource(
        155,
        isSourceEnabled: (_) => false,
      );

      expect(result, isNull);
    });
  });

  group('PlayerScreen.limitAutoCaptureCandidates (cap to 2)', () {
    test('maxAutoCaptureProviders caps the dead wait', () {
      expect(PlayerScreen.maxAutoCaptureProviders, 2);
    });

    test('truncates a longer list to the cap, keeping registry order', () {
      final all = PlayerScreen.buildAutoCaptureCandidates(
        1081003,
        isSourceEnabled: (_) => true,
      );
      expect(all.length, greaterThan(PlayerScreen.maxAutoCaptureProviders));

      final limited = PlayerScreen.limitAutoCaptureCandidates(
        all,
        PlayerScreen.maxAutoCaptureProviders,
      );

      expect(limited.length, PlayerScreen.maxAutoCaptureProviders);
      expect(limited.first.sourceId, all.first.sourceId);
      expect(limited.last.sourceId, all[1].sourceId);
    });

    test('keeps the list unchanged when it is already at or under the cap', () {
      final one = PlayerScreen.buildAutoCaptureCandidates(
        155,
        isSourceEnabled: (id) => id == 'vidlink',
      );
      final limited = PlayerScreen.limitAutoCaptureCandidates(
        one,
        PlayerScreen.maxAutoCaptureProviders,
      );

      expect(identical(limited, one), isTrue);
    });

    test('handles an empty list', () {
      final limited = PlayerScreen.limitAutoCaptureCandidates(
        const <VideoSource>[],
        PlayerScreen.maxAutoCaptureProviders,
      );
      expect(limited, isEmpty);
    });
  });

  group('PlayerScreen.buildAutoCaptureCandidates', () {
    test('returns every enabled provider with an embed URL, in registry order',
        () {
      final result = PlayerScreen.buildAutoCaptureCandidates(
        1081003,
        isSourceEnabled: (_) => true,
      );

      // Registry order = reliability order: VidLink + 2Embed.skin (the
      // proven-alive pair on-device) come first so the auto-capture cap of 2
      // keeps them; the ISP-blocked vidsrc.to and blank-serving 2embed.cc
      // are pushed to the back.
      expect(
        result.map((c) => c.sourceId).toList(),
        ['vidlink', 'two_embed_skin', 'vidsrc_to', 'two_embed', 'vidsrc_su'],
      );
      for (final candidate in result) {
        expect(candidate.embedUrl, isNotNull);
        expect(candidate.embedUrl, contains('1081003'));
      }
    });

    test('skips disabled providers but keeps the remaining ones', () {
      final result = PlayerScreen.buildAutoCaptureCandidates(
        155,
        isSourceEnabled: (id) => id != 'vidsrc_to',
      );

      expect(result, isNotEmpty);
      expect(result.any((c) => c.sourceId == 'vidsrc_to'), isFalse);
      // VidLink is first in the reliability-ordered registry.
      expect(result.first.sourceId, 'vidlink');
    });

    test('returns empty when every provider is disabled', () {
      final result = PlayerScreen.buildAutoCaptureCandidates(
        155,
        isSourceEnabled: (_) => false,
      );

      expect(result, isEmpty);
    });

    test('first candidate matches buildFallbackWebViewSource', () {
      final all = PlayerScreen.buildAutoCaptureCandidates(
        969681,
        isSourceEnabled: (_) => true,
      );
      final fallback = PlayerScreen.buildFallbackWebViewSource(
        969681,
        isSourceEnabled: (_) => true,
      );

      expect(all, isNotEmpty);
      expect(fallback?.sourceId, all.first.sourceId);
      expect(fallback?.embedUrl, all.first.embedUrl);
    });
  });

  group('PlayerScreen.nextAutoCaptureIndex', () {
    test('advances within bounds', () {
      expect(PlayerScreen.nextAutoCaptureIndex(0, 6), 1);
      expect(PlayerScreen.nextAutoCaptureIndex(4, 6), 5);
    });

    test('returns null when every candidate has been tried', () {
      expect(PlayerScreen.nextAutoCaptureIndex(5, 6), isNull);
      expect(PlayerScreen.nextAutoCaptureIndex(0, 0), isNull);
    });
  });

  group('PlayerScreen.shouldReArmAutoHandoff (mpv failure loop guard)', () {
    test(
        'first mpv failure re-arms auto-handoff (WebView can capture a '
        'working URL and hand it back to the native player)', () {
      expect(PlayerScreen.shouldReArmAutoHandoff(1), isTrue);
    });

    test('second mpv failure disables auto-handoff (no infinite bounce)', () {
      expect(PlayerScreen.shouldReArmAutoHandoff(2), isFalse);
      expect(PlayerScreen.shouldReArmAutoHandoff(3), isFalse);
      expect(PlayerScreen.shouldReArmAutoHandoff(99), isFalse);
    });

    test('no failure yet → nothing to re-arm', () {
      expect(PlayerScreen.shouldReArmAutoHandoff(0), isFalse);
    });
  });

  group('WebViewPlayerScreen error surfacing (main-frame + URL match)', () {
    test('load error surfaces only for the main document at the original URL',
        () {
      const embedUrl = 'https://vidsrc.to/embed/movie/155';
      expect(
        WebViewPlayerScreen.shouldSurfaceLoadError(
          isForMainFrame: true,
          requestUrl: embedUrl,
          expectedUrl: embedUrl,
        ),
        isTrue,
      );
      // Sub-frame ad/tracker errors must never cover the playing video.
      expect(
        WebViewPlayerScreen.shouldSurfaceLoadError(
          isForMainFrame: false,
          requestUrl: embedUrl,
          expectedUrl: embedUrl,
        ),
        isFalse,
      );
      expect(
        WebViewPlayerScreen.shouldSurfaceLoadError(
          isForMainFrame: null,
          requestUrl: embedUrl,
          expectedUrl: embedUrl,
        ),
        isFalse,
      );
      // A main-frame failure on a DIFFERENT URL (e.g. a frame that was
      // hijacked to an ad landing page) must never cover the player either.
      expect(
        WebViewPlayerScreen.shouldSurfaceLoadError(
          isForMainFrame: true,
          requestUrl: 'https://ads.example.com/landing',
          expectedUrl: embedUrl,
        ),
        isFalse,
      );
    });

    test('http error surfaces only for the main document at the original URL',
        () {
      const embedUrl = 'https://vidsrc.to/embed/movie/155';
      expect(
        WebViewPlayerScreen.shouldSurfaceHttpError(
          isForMainFrame: true,
          requestUrl: embedUrl,
          expectedUrl: embedUrl,
        ),
        isTrue,
      );
      // Sub-frame 404/403 from ads/trackers: ignored.
      expect(
        WebViewPlayerScreen.shouldSurfaceHttpError(
          isForMainFrame: false,
          requestUrl: embedUrl,
          expectedUrl: embedUrl,
        ),
        isFalse,
      );
      // After a redirect (vidsrc.to → vsembed.ru) the URL no longer matches:
      // the source's own page (with its own error UI) is shown instead.
      expect(
        WebViewPlayerScreen.shouldSurfaceHttpError(
          isForMainFrame: true,
          requestUrl: 'https://vsembed.ru/embed/movie/155',
          expectedUrl: embedUrl,
        ),
        isFalse,
      );
    });
  });

  group('WebViewPlayerScreen ad-blocking', () {
    test('blocks known ad/tracker hosts', () {
      expect(
        WebViewPlayerScreen.isAdHost('pagead2.googlesyndication.com'),
        isTrue,
      );
      expect(WebViewPlayerScreen.isAdHost('ads.doubleclick.net'), isTrue);
      expect(WebViewPlayerScreen.isAdHost('cdn.popads.net'), isTrue);
      expect(WebViewPlayerScreen.isAdHost('a.applovin.com'), isTrue);
      expect(WebViewPlayerScreen.isAdHost('ads.taboola.com'), isTrue);
      expect(WebViewPlayerScreen.isAdHost('bid.g.doubleclick.net'), isTrue);
    });

    test('allows real source and media hosts', () {
      expect(WebViewPlayerScreen.isAdHost('vidlink.pro'), isFalse);
      expect(WebViewPlayerScreen.isAdHost('2embed.skin'), isFalse);
      expect(WebViewPlayerScreen.isAdHost('streamsrcs.2embed.cc'), isFalse);
      expect(WebViewPlayerScreen.isAdHost('cdn.example.com'), isFalse);
      expect(WebViewPlayerScreen.isAdHost(''), isFalse);
    });
  });

  group('StreamCaptureCore shared helpers', () {
    test('embedIsMediaUrl captures .m3u8/.mp4 with query & fragment', () {
      expect(embedIsMediaUrl('https://cdn.example.com/hls/index.m3u8'), isTrue);
      expect(
        embedIsMediaUrl(
          'https://cdn.example.com/movie.mp4?token=abc&exp=123#t=10',
        ),
        isTrue,
      );
      expect(embedIsMediaUrl('https://cdn.example.com/a.m3u8?x=1'), isTrue);
    });

    test('embedIsMediaUrl rejects non-media and empty URLs', () {
      expect(embedIsMediaUrl(''), isFalse);
      expect(embedIsMediaUrl('https://cdn.example.com/seg00001.ts'), isFalse);
      expect(embedIsMediaUrl('https://cdn.example.com/hls.min.js'), isFalse);
      expect(embedIsMediaUrl('https://cdn.example.com/player.css'), isFalse);
      expect(embedIsMediaUrl('https://cdn.example.com/poster.jpg'), isFalse);
    });

    test('embedIsNativeStreamCandidate requires plain http(s) non-blob', () {
      const embed = 'https://embed.example.com/e/1';
      expect(
        embedIsNativeStreamCandidate(
          'https://cdn.example.com/master.m3u8',
          embedUrl: embed,
        ),
        isTrue,
      );
      expect(
        embedIsNativeStreamCandidate('blob:https://cdn/x', embedUrl: embed),
        isFalse,
      );
      expect(
        embedIsNativeStreamCandidate('', embedUrl: embed),
        isFalse,
      );
      // The embed page itself is never a native candidate.
      expect(
        embedIsNativeStreamCandidate(embed, embedUrl: embed),
        isFalse,
      );
    });

    test('embedIsAdHost matches known ad network fragments', () {
      expect(embedIsAdHost('adservice.google.com'), isTrue);
      expect(embedIsAdHost('cdn.example.com'), isFalse);
      expect(embedIsAdHost(''), isFalse);
    });
  });

  group('WebViewPlayerScreen network media capture', () {
    test('captures .m3u8/.mp4 manifest URLs (with query/fragment)', () {
      expect(
        WebViewPlayerScreen.isMediaUrl(
          'https://cdn.example.com/hls/index.m3u8',
        ),
        isTrue,
      );
      expect(
        WebViewPlayerScreen.isMediaUrl(
          'https://cdn.example.com/movie.mp4?token=abc&exp=123#t=10',
        ),
        isTrue,
      );
    });

    test('rejects segments, scripts, CSS and images', () {
      expect(
        WebViewPlayerScreen.isMediaUrl('https://cdn.example.com/seg00001.ts'),
        isFalse,
      );
      expect(
        WebViewPlayerScreen.isMediaUrl('https://cdn.example.com/hls.min.js'),
        isFalse,
      );
      expect(
        WebViewPlayerScreen.isMediaUrl('https://cdn.example.com/player.css'),
        isFalse,
      );
      expect(
        WebViewPlayerScreen.isMediaUrl('https://cdn.example.com/poster.jpg'),
        isFalse,
      );
      expect(WebViewPlayerScreen.isMediaUrl(''), isFalse);
    });
  });

  group('WebViewPlayerArgs autoHandoff flag', () {
    test('defaults to enabled', () {
      const args = WebViewPlayerArgs(
        url: 'https://vidlink.pro/movie/155',
        sourceLabel: 'VidLink',
      );
      expect(args.autoHandoff, isTrue);
    });

    test('can be disabled (mpv-failed loop guard)', () {
      const args = WebViewPlayerArgs(
        url: 'https://vidlink.pro/movie/155',
        sourceLabel: 'VidLink',
        autoHandoff: false,
      );
      expect(args.autoHandoff, isFalse);
    });
  });

  group('WebViewPlayerScreen blank-page detection', () {
    test('isBlankProbe is true for about:blank/empty-body probes', () {
      expect(
        WebViewPlayerScreen.isBlankProbe(const {'url': '', 'blank': true}),
        isTrue,
      );
    });

    test('isBlankProbe is false for a page with content or a video', () {
      expect(
        WebViewPlayerScreen.isBlankProbe(const {'url': '', 'blank': false}),
        isFalse,
      );
      expect(
        WebViewPlayerScreen.isBlankProbe(const {'url': 'https://cdn/x.mp4'}),
        isFalse,
      );
    });

    test('blank error surfaces only after the threshold', () {
      expect(
        WebViewPlayerScreen.shouldSurfaceBlankError(
          WebViewPlayerScreen.blankProbeThreshold - 1,
        ),
        isFalse,
      );
      expect(
        WebViewPlayerScreen.shouldSurfaceBlankError(
          WebViewPlayerScreen.blankProbeThreshold,
        ),
        isTrue,
      );
    });
  });

  group('WebViewPlayerScreen.advanceStableProbe (auto-handoff)', () {
    test('increments when playback position advances', () {
      expect(
        WebViewPlayerScreen.advanceStableProbe(
          position: const Duration(seconds: 4),
          lastPosition: const Duration(seconds: 2),
          count: 2,
        ),
        3,
      );
    });

    test('resets when position stalls (paused/buffering)', () {
      expect(
        WebViewPlayerScreen.advanceStableProbe(
          position: const Duration(seconds: 2),
          lastPosition: const Duration(seconds: 2),
          count: 2,
        ),
        0,
      );
    });

    test('resets when position goes backwards (seek/restart)', () {
      expect(
        WebViewPlayerScreen.advanceStableProbe(
          position: const Duration(seconds: 2),
          lastPosition: const Duration(seconds: 8),
          count: 2,
        ),
        0,
      );
    });

    test('first probe counts as an advance from zero', () {
      expect(
        WebViewPlayerScreen.advanceStableProbe(
          position: const Duration(milliseconds: 300),
          lastPosition: Duration.zero,
          count: 0,
        ),
        1,
      );
    });

    test('zero position never counts as an advance', () {
      expect(
        WebViewPlayerScreen.advanceStableProbe(
          position: Duration.zero,
          lastPosition: Duration.zero,
          count: 3,
        ),
        0,
      );
    });

    test('requires strictly consecutive advancing probes to reach threshold',
        () {
      // 3 stable probes needed; a single stall resets the counter.
      var count = 0;
      var last = Duration.zero;
      count = WebViewPlayerScreen.advanceStableProbe(
        position: const Duration(seconds: 1),
        lastPosition: last,
        count: count,
      );
      last = const Duration(seconds: 1);
      count = WebViewPlayerScreen.advanceStableProbe(
        position: const Duration(seconds: 2),
        lastPosition: last,
        count: count,
      );
      last = const Duration(seconds: 2);
      // stall
      count = WebViewPlayerScreen.advanceStableProbe(
        position: const Duration(seconds: 2),
        lastPosition: last,
        count: count,
      );
      expect(count, 0);

      // Now 3 clean advances in a row reach the threshold.
      count = WebViewPlayerScreen.advanceStableProbe(
        position: const Duration(seconds: 3),
        lastPosition: last,
        count: count,
      );
      last = const Duration(seconds: 3);
      count = WebViewPlayerScreen.advanceStableProbe(
        position: const Duration(seconds: 4),
        lastPosition: last,
        count: count,
      );
      last = const Duration(seconds: 4);
      count = WebViewPlayerScreen.advanceStableProbe(
        position: const Duration(seconds: 5),
        lastPosition: last,
        count: count,
      );
      expect(count, WebViewPlayerScreen.stableProbeThreshold);
    });
  });

  group('WebViewPlayerScreen native stream handoff', () {
    test('accepts plain http(s) media URLs', () {
      expect(
        WebViewPlayerScreen.isNativeStreamCandidate(
          'https://cdn.example.com/video/index.m3u8',
          embedUrl: 'https://vidlink.pro/movie/155',
        ),
        isTrue,
      );
      expect(
        WebViewPlayerScreen.isNativeStreamCandidate(
          'http://cdn.example.com/movie.mp4',
          embedUrl: 'https://vidlink.pro/movie/155',
        ),
        isTrue,
      );
    });

    test('rejects blob:, empty, and the embed page itself', () {
      expect(
        WebViewPlayerScreen.isNativeStreamCandidate(
          '',
          embedUrl: 'https://v.p/m',
        ),
        isFalse,
      );
      expect(
        WebViewPlayerScreen.isNativeStreamCandidate(
          'blob:https://v.p/abc-123',
          embedUrl: 'https://v.p/m',
        ),
        isFalse,
      );
      expect(
        WebViewPlayerScreen.isNativeStreamCandidate(
          'https://vidlink.pro/movie/155',
          embedUrl: 'https://vidlink.pro/movie/155',
        ),
        isFalse,
      );
    });
  });

  group('ErrorView secondary action', () {
    testWidgets('renders Retry only when no secondary action is given',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorView(message: 'Something failed', onRetry: _noop),
          ),
        ),
      );

      expect(find.text('Something failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Play in WebView'), findsNothing);
      expect(find.text('May show source ads'), findsNothing);
    });

    testWidgets('renders secondary button + hint when provided',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorView(
              message: 'Failed to load',
              onRetry: _noop,
              secondaryLabel: 'Play in WebView',
              onSecondary: () => tapped = true,
              secondaryHint: 'May show source ads',
            ),
          ),
        ),
      );

      expect(find.text('Play in WebView'), findsOneWidget);
      expect(find.text('May show source ads'), findsOneWidget);

      await tester.tap(find.text('Play in WebView'));
      expect(tapped, isTrue);
    });

    testWidgets('does not render hint when secondaryHint is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorView(
              message: 'Failed to load',
              onRetry: _noop,
              secondaryLabel: 'Open embed',
              onSecondary: _noop,
            ),
          ),
        ),
      );

      expect(find.text('Open embed'), findsOneWidget);
      expect(find.text('May show source ads'), findsNothing);
    });
  });

  group('WebViewPlayerScreen.formatCookieHeader', () {
    test('joins cookies into one Cookie header value', () {
      expect(
        WebViewPlayerScreen.formatCookieHeader([
          Cookie(name: 'session', value: 'abc123'),
          Cookie(name: 'region', value: 'id'),
        ]),
        'session=abc123; region=id',
      );
    });

    test('empty list => empty header', () {
      expect(WebViewPlayerScreen.formatCookieHeader([]), '');
    });
  });

  group('HiddenStreamCapture non-playable URL rejection (VidLink 428 class)',
      () {
    test('empty headers={} template URL is NOT directly playable', () {
      expect(
        StreamSourceDataSource.isDirectPlayableUrl(
          'https://noir.suubmon.store/mp/resource/abc.mp4'
          '?sign=x&t=1785546276&headers=%7B%7D'
          '&host=https%3A%2F%2Fbcdn.example.com',
        ),
        isFalse,
      );
      // Lowercase percent-encoding must also be rejected.
      expect(
        StreamSourceDataSource.isDirectPlayableUrl(
          'https://cdn.example.com/v.mp4?headers=%7b%7d&sign=x',
        ),
        isFalse,
      );
    });

    test('filled or absent headers param remains playable', () {
      expect(
        StreamSourceDataSource.isDirectPlayableUrl(
          'https://cdn.example.com/v.mp4?headers=abc&sign=x',
        ),
        isTrue,
      );
      expect(
        StreamSourceDataSource.isDirectPlayableUrl(
          'https://cdn.example.com/v.m3u8?token=abc',
        ),
        isTrue,
      );
    });

    test('give-up triggers only after the consecutive-rejection threshold', () {
      expect(
        HiddenStreamCapture.shouldGiveUpOnNonPlayable(
          HiddenStreamCapture.nonPlayableGiveUpThreshold - 1,
        ),
        isFalse,
      );
      expect(
        HiddenStreamCapture.shouldGiveUpOnNonPlayable(
          HiddenStreamCapture.nonPlayableGiveUpThreshold,
        ),
        isTrue,
      );
    });

    test('cdnFailureKey normalizes signed URLs to a stable identity', () {
      // Signed URLs rotate their token on every retry — the give-up counter
      // must accumulate on scheme+host+path, not the full URL.
      final a = HiddenStreamCapture.cdnFailureKey(
        'https://noir.suubmon.store/mp/resource/a.mp4?sign=1&t=100',
      );
      final b = HiddenStreamCapture.cdnFailureKey(
        'https://noir.suubmon.store/mp/resource/a.mp4?sign=2&t=200',
      );
      expect(a, b);
      expect(a, 'https://noir.suubmon.store/mp/resource/a.mp4');
    });
  });
}

void _noop() {}
