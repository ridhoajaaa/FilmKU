import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/core/net/hls_relay.dart';
import 'package:filmku/features/movies/domain/entities/video_source.dart';
import 'package:filmku/features/movies/presentation/screens/player_screen.dart';
import 'package:filmku/features/movies/data/datasources/stream_source_datasource.dart';
import 'package:filmku/features/movies/presentation/widgets/error_view.dart';
import 'package:filmku/features/movies/presentation/widgets/hidden_stream_capture.dart';
import 'package:filmku/features/movies/presentation/widgets/stream_capture_core.dart';

/// Tests for the WebView fallback player wiring.
void main() {
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

    test('returns null when every candidate has been tried', () {
      expect(PlayerScreen.nextAutoCaptureIndex(5, 6), isNull);
      expect(PlayerScreen.nextAutoCaptureIndex(0, 0), isNull);
    });
  });

  group('disable-devtool neutralization (2embed iOS capture fix)', () {
    test('flags the disable-devtool script URL and its 404 redirect host', () {
      expect(
        embedIsDisableDevtoolUrl(
          'https://cdn.jsdelivr.net/npm/disable-devtool@latest',
        ),
        isTrue,
      );
      expect(
        embedIsDisableDevtoolUrl(
          'https://theajack.github.io/disable-devtool/404.html'
          '?h=www.2embed.skin',
        ),
        isTrue,
      );
      // The data-layer copy used by the headless extractor must agree.
      expect(
        StreamSourceDataSource.isDisableDevtoolUrl(
          'https://cdn.jsdelivr.net/npm/disable-devtool@latest',
        ),
        isTrue,
      );
      expect(
        StreamSourceDataSource.isDisableDevtoolUrl(
          'https://theajack.github.io/disable-devtool/404.html?h=x',
        ),
        isTrue,
      );
    });

    test('never flags real source/player/media URLs', () {
      expect(embedIsDisableDevtoolUrl('https://www.2embed.skin/e/1'), isFalse);
      expect(
        embedIsDisableDevtoolUrl('https://streamsrcs.2embed.cc/swish?id=x'),
        isFalse,
      );
      expect(
        embedIsDisableDevtoolUrl('https://cdn.example.com/player.js'),
        isFalse,
      );
      expect(
        embedIsDisableDevtoolUrl('https://cdn.example.com/master.m3u8'),
        isFalse,
      );
      expect(embedIsDisableDevtoolUrl(''), isFalse);
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

  group('StreamSourceDataSource.2embed direct-player resolution', () {
    test('parses swish id from shell data-src and builds the 2vcdn URL', () {
      const html = '<iframe id="iframesrc" src="about:blank" '
          'data-src="https://streamsrcs.2embed.cc/swish?id=4rc2jaa92ugh'
          '&ref=mdrct"></iframe>';
      expect(
        StreamSourceDataSource.resolveTwoEmbedSwishId(html),
        '4rc2jaa92ugh',
      );
      expect(
        StreamSourceDataSource.buildTwoEmbedPlayerUrl(html),
        'https://2vcdn.skin/e/4rc2jaa92ugh',
      );
    });

    test('decodes entity-encoded ampersands before parsing', () {
      const html = '<iframe '
          'data-src="https://streamsrcs.2embed.cc/swish?id=ab12cd34'
          '&amp;ref=mdrct"></iframe>';
      expect(
        StreamSourceDataSource.resolveTwoEmbedSwishId(html),
        'ab12cd34',
      );
    });

    test('returns null when the shell has no swish data-src', () {
      const html = '<html><body>no player here</body></html>';
      expect(StreamSourceDataSource.resolveTwoEmbedSwishId(html), isNull);
      expect(StreamSourceDataSource.buildTwoEmbedPlayerUrl(html), isNull);
    });

    test('parses the NEW vnest tmdb from shell data-src (2026-08 rotation)',
        () {
      const html = '<iframe id="iframesrc" src="about:blank" '
          'data-src="https://streamsrcs.2embed.cc/vnest?tmdb=634649"></iframe>';
      expect(StreamSourceDataSource.resolveTwoEmbedVnestTmdb(html), '634649');
      expect(
        StreamSourceDataSource.buildTwoEmbedVnestUrl(html),
        'https://streamsrcs.2embed.cc/vnest?tmdb=634649',
      );
    });

    test('vnest parser decodes entity-encoded ampersands', () {
      const html = '<iframe '
          'data-src="https://streamsrcs.2embed.cc/vnest?tmdb=969681'
          '&amp;x=1"></iframe>';
      expect(StreamSourceDataSource.resolveTwoEmbedVnestTmdb(html), '969681');
    });

    test('vnest parser returns null when the shell uses the legacy swish', () {
      const html = '<iframe '
          'data-src="https://streamsrcs.2embed.cc/swish?id=ab12cd34'
          '&ref=mdrct"></iframe>';
      expect(StreamSourceDataSource.resolveTwoEmbedVnestTmdb(html), isNull);
      expect(StreamSourceDataSource.buildTwoEmbedVnestUrl(html), isNull);
    });

    test('resolution builders cover BOTH chains (legacy swish + new vnest)',
        () {
      // Legacy chain wins when both structures are present (native playable).
      const legacy = '<iframe '
          'data-src="https://streamsrcs.2embed.cc/swish?id=4rc2jaa92ugh'
          '&ref=mdrct" data-x="https://streamsrcs.2embed.cc/vnest?tmdb=1">'
          '</iframe>';
      // No live network here — the pure builders decide the priority.
      expect(
        StreamSourceDataSource.buildTwoEmbedPlayerUrl(legacy),
        'https://2vcdn.skin/e/4rc2jaa92ugh',
      );
      // Vnest-only shell → the new player page is the resolution target.
      const vnest = '<iframe '
          'data-src="https://streamsrcs.2embed.cc/vnest?tmdb=155"></iframe>';
      expect(StreamSourceDataSource.buildTwoEmbedPlayerUrl(vnest), isNull);
      expect(
        StreamSourceDataSource.buildTwoEmbedVnestUrl(vnest),
        'https://streamsrcs.2embed.cc/vnest?tmdb=155',
      );
    });

    test('isTwoEmbedShellUrl covers both .skin and legacy .cc domains', () {
      expect(
        StreamSourceDataSource.isTwoEmbedShellUrl(
          'https://www.2embed.skin/embed/movie/155',
        ),
        isTrue,
      );
      expect(
        StreamSourceDataSource.isTwoEmbedShellUrl(
          'https://www.2embed.cc/embed/movie/155',
        ),
        isTrue,
      );
      expect(
        StreamSourceDataSource.isTwoEmbedShellUrl(
            'https://vidlink.pro/movie/155'),
        isFalse,
      );
      expect(StreamSourceDataSource.isTwoEmbedShellUrl(''), isFalse);
    });
  });

  group('StreamSourceDataSource.isTwoEmbedKillerNavigation', () {
    test('cancels the 2vcdn anti-frame root redirect', () {
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation(
          'https://2vcdn.skin/',
        ),
        isTrue,
      );
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation('https://2vcdn.skin'),
        isTrue,
      );
      // The actual player page must NOT be cancelled.
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation(
          'https://2vcdn.skin/e/4rc2jaa92ugh',
        ),
        isFalse,
      );
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation(
          'https://2vcdn.skin/stream/x/master.m3u8',
        ),
        isFalse,
      );
    });

    test('cancels the shell movie/movie redirect but not the embed page', () {
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation(
          'https://www.2embed.skin/movie/movie/1481343',
        ),
        isTrue,
      );
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation(
          'https://www.2embed.skin/embed/movie/1481343',
        ),
        isFalse,
      );
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation(
          'https://www.2embed.cc/embed/movie/1481343',
        ),
        isFalse,
      );
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation(
          'https://vidlink.pro/movie/155',
        ),
        isFalse,
      );
    });
    test('cancels the NEW vnest anti-frame root redirect (2026-08)', () {
      // The vnest page's guard: `location.replace("https://www.2embed.cc/")`
      // — with and without www, root only.
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation(
          'https://www.2embed.cc/',
        ),
        isTrue,
      );
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation(
            'https://www.2embed.cc'),
        isTrue,
      );
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation('https://2embed.cc/'),
        isTrue,
      );
      // The REAL 2embed.cc embed pages keep their path — never cancelled.
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation(
          'https://www.2embed.cc/embed/movie/1481343',
        ),
        isFalse,
      );
      // The vnest player page itself and its cineby target stay allowed.
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation(
          'https://streamsrcs.2embed.cc/vnest?tmdb=155',
        ),
        isFalse,
      );
      expect(
        StreamSourceDataSource.isTwoEmbedKillerNavigation(
          'https://cineby.hair/movie/155?autostart=true',
        ),
        isFalse,
      );
    });
  });

  group('StreamSourceDataSource 2vcdn direct extraction', () {
    test('jsUnescape handles backslash escapes', () {
      expect(StreamSourceDataSource.jsUnescape(r'http:\/\/x'), 'http://x');
      expect(StreamSourceDataSource.jsUnescape(r"'it\'s"), "'it's");
      expect(StreamSourceDataSource.jsUnescape(r'\x41\u0042'), 'AB');
    });

    test('radixToBase encodes key indices with the packer radix', () {
      // 2vcdn uses radix 36 (not the classic 62): token d4 == index 472
      // (vplayer) only in base 36.
      expect(StreamSourceDataSource.radixToBase(0, 36), '0');
      expect(StreamSourceDataSource.radixToBase(10, 36), 'a');
      expect(StreamSourceDataSource.radixToBase(35, 36), 'z');
      expect(StreamSourceDataSource.radixToBase(36, 36), '10');
      expect(StreamSourceDataSource.radixToBase(472, 36), 'd4');
      expect(StreamSourceDataSource.radixToBase(132, 36), '3o');
    });

    test('unpackDeanEdwards decodes a minimal packed block', () {
      // Minimal packer wrapper (the parser keys off `return p}(` — the real
      // packer function body is irrelevant to decoding): keys [stream,
      // master] at indices 0/1, body refers to them as base-62 tokens.
      const packed = "eval(function(p,a,c,k,e,d){return p}("
          "'1 0',62,2,'stream|master'.split('|')))";
      expect(StreamSourceDataSource.unpackDeanEdwards(packed), 'master stream');
    });

    test('unpackDeanEdwards returns null for a non-packer page', () {
      expect(StreamSourceDataSource.unpackDeanEdwards('<html>no packer</html>'),
          isNull);
    });

    test('unpackDeanEdwards resists embedded \',digits,digits,\' fragments',
        () {
      // The payload embeds a packed string literal `\',62,2,'` — the exact
      // pattern that truncated the old non-greedy `.*?'` regex (group(1) cut
      // at the ESCAPED quote inside the payload). The robust lastIndexOf
      // slice + wrapping-quote strip must decode the WHOLE payload, and the
      // `,62,2,'keys'` boundary must still be found at the real terminator.
      const packed = "eval(function(p,a,c,k,e,d){return p}("
          "'var x=\\',62,2,';file:\"/stream/1/master.m3u8\";',62,2,"
          "'stream|master'.split('|')))";
      final body = StreamSourceDataSource.unpackDeanEdwards(packed);
      expect(body, isNotNull);
      // The embedded `',62,2,'` string literal survived unescaped AND the
      // token substitution still ran (index 1 -> master).
      expect(body, contains("var x=',62,2,';"));
      expect(body, contains('/stream/master/master.m3u8'));
    });

    test('extractTwoVcdnStreamPath finds the /stream/.../master.m3u8 path', () {
      const body = 'var n={"15":"x"};jwplayer("vplayer").setup({';
      const withUrl = '$body sources:[{file:"/stream/QPdJLigcsVdATv6VtHUHfw/'
          'kjhhiuahiuhgihdf/1785939409/73649149/master.m3u8"}]});';
      expect(
        StreamSourceDataSource.extractTwoVcdnStreamPath(withUrl),
        '/stream/QPdJLigcsVdATv6VtHUHfw/kjhhiuahiuhgihdf/'
        '1785939409/73649149/master.m3u8',
      );
    });

    test('extractTwoVcdnStreamPath handles the dash-joined rotating token', () {
      const body = 'file:"/stream/04qp0Us4Ni-62t2OfjrzBw/kjhhiuahiuhgihdf/'
          '1785939685/73649149/master.m3u8"';
      expect(
        StreamSourceDataSource.extractTwoVcdnStreamPath(body),
        '/stream/04qp0Us4Ni-62t2OfjrzBw/kjhhiuahiuhgihdf/'
        '1785939685/73649149/master.m3u8',
      );
    });

    test('extractTwoVcdnStreamPath returns null when absent', () {
      expect(StreamSourceDataSource.extractTwoVcdnStreamPath('no stream here'),
          isNull);
    });

    test('streamUrlFromTwoVcdnPage needs the eval packer', () {
      expect(StreamSourceDataSource.streamUrlFromTwoVcdnPage('<html>'), isNull);
    });

    test('streamUrlFromTwoVcdnPage resolves relative stream path to absolute',
        () {
      // Packed body that unpacks to a setup call containing the stream path.
      final packed = _buildPacked(
        '/stream/QPdJLigcsVdATv6VtHUHfw/kjhhiuahiuhgihdf/'
        '1785939409/73649149/master.m3u8',
      );
      final page = '<html><script>$packed</script></html>';
      expect(
        StreamSourceDataSource.streamUrlFromTwoVcdnPage(page),
        'https://2vcdn.skin/stream/QPdJLigcsVdATv6VtHUHfw/kjhhiuahiuhgihdf/'
        '1785939409/73649149/master.m3u8',
      );
    });
  });

  group('HlsRelay stripPngWrapper', () {
    test('strips the constant 70-byte fake-PNG wrapper', () {
      final ts = Uint8List.fromList(
        List<int>.generate(
            188 * 3, (i) => i == 0 || i == 188 || i == 376 ? 0x47 : (i % 251)),
      );
      final wrapped = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
        ...List<int>.filled(62, 0x00), // rest of the 70-byte wrapper
        ...ts,
      ]);
      final stripped = HlsRelay.stripPngWrapper(wrapped);
      expect(stripped.length, ts.length);
      expect(stripped[0], 0x47);
      expect(stripped[188], 0x47);
    });

    test('passes through non-PNG data untouched', () {
      final raw = Uint8List.fromList(List<int>.generate(300, (i) => i % 256));
      expect(HlsRelay.stripPngWrapper(raw), same(raw));
    });

    test('passes through short buffers untouched', () {
      final tiny = Uint8List.fromList([1, 2, 3]);
      expect(HlsRelay.stripPngWrapper(tiny), same(tiny));
    });
  });

  group('embedNeutralizeAntiFrameScript', () {
    test('aliases the data-layer canonical script', () {
      expect(
        embedNeutralizeAntiFrameScript,
        StreamSourceDataSource.neutralizeAntiFrameScript,
      );
    });

    test('overrides Location.prototype.replace for the root redirect', () {
      const s = embedNeutralizeAntiFrameScript;
      expect(s, contains('Location.prototype'));
      expect(s, contains('replace'));
      // Must only no-op the anti-frame root redirect — real navigations
      // (including the actual 2vcdn player URL) must still proceed.
      expect(s, contains('s==="/"'));
      expect(s, isNot(contains('location.href')));
    });
  });
}

/// Builds a Dean-Edwards-packed block whose payload unpacks to a string that
/// contains [streamPath] (as the 2vcdn player's `file:` value would). The
/// path is passed through the key array as a single literal so the unpacker
/// round-trips it verbatim.
String _buildPacked(String streamPath) {
  // body '1 0' unpacks to `{streamPath} file` — the stream path appears in
  // the decoded output, which is all streamUrlFromTwoVcdnPage needs.
  return "eval(function(p,a,c,k,e,d){return p}("
      "'1 0',62,2,'file|$streamPath'.split('|')))";
}

void _noop() {}
