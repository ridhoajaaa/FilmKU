import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/features/movies/data/datasources/stream_source_datasource.dart';

/// Unit tests for [StreamSourceDataSource.shouldCaptureUrl] — the shared
/// filter used by the headless WebView extractor's `capture()` helper.
///
/// The filter must accept real `.m3u8`/`.mp4` URLs (including ones with query
/// strings, e.g. signed VidLink links) while rejecting script/CSS/image
/// resources that merely *substring-match* `looksLikeVideo` — e.g. a file
/// named `hls.m3u8.min.js` must NOT stop the extraction with a false hit.
void main() {
  group('StreamSourceDataSource.shouldCaptureUrl', () {
    test('accepts a plain .m3u8 HLS playlist', () {
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/hls/master.m3u8',
        ),
        isTrue,
      );
    });

    test('accepts an .m3u8 URL with a query string (tokenized playlists)', () {
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/hls/master.m3u8?token=abc123&expiry=9999',
        ),
        isTrue,
      );
    });

    test('accepts an .m3u8 URL with a fragment (#)', () {
      // Fragments (e.g. #t=0,60 time offsets) do not change the media path
      // and must not break capture detection.
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/hls/master.m3u8#t=0,60',
        ),
        isTrue,
      );
      // Combined query + fragment — both stripped before the path check.
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/hls/master.m3u8?token=abc#frag',
        ),
        isTrue,
      );
    });

    test('accepts a plain .mp4 file', () {
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/video/1080p.mp4',
        ),
        isTrue,
      );
    });

    test('accepts a VidLink-style signed .mp4 with query params', () {
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://noir.suubmon.store/mp/resource/h265/'
          '0d7f95526e8962a442d1ae22b06c2914.mp4?'
          'sign=ba62a57554925d3ba0614f7b73859292&t=1785258198',
        ),
        isTrue,
      );
    });

    test('accepts an .mp4 URL with query params', () {
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/video/movie.mp4?bitrate=2500',
        ),
        isTrue,
      );
    });

    test('accepts a trailing-slash .m3u8 redirect URL', () {
      // Some CDNs serve HLS playlists with a trailing slash and redirect.
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/hls/master.m3u8/',
        ),
        isTrue,
      );
    });

    test('rejects a script file whose name contains .m3u8', () {
      // A player bundle named like this substring-matches looksLikeVideo but
      // is a script — must not be captured as a playable stream.
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/js/hls.m3u8.min.js',
        ),
        isFalse,
      );
    });

    test('rejects a script file whose name contains .mp4', () {
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/js/player.mp4.loader.js',
        ),
        isFalse,
      );
    });

    test('rejects a stylesheet whose name contains .m3u8', () {
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/css/player.m3u8.css',
        ),
        isFalse,
      );
    });

    test('rejects a plain .js script URL', () {
      // Player bundles without any video marker in the name must also be
      // filtered — a bare .js file is never a playable stream.
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/js/player.bundle.js',
        ),
        isFalse,
      );
    });

    test('rejects a plain .css stylesheet URL', () {
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/css/player.css',
        ),
        isFalse,
      );
    });

    test('rejects image assets whose names contain video markers', () {
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/img/hls.m3u8.png',
        ),
        isFalse,
      );
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/img/movie.mp4.jpg',
        ),
        isFalse,
      );
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/img/hls.m3u8.webp',
        ),
        isFalse,
      );
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/img/stream.m3u8.svg',
        ),
        isFalse,
      );
    });

    test('rejects an empty string', () {
      expect(StreamSourceDataSource.shouldCaptureUrl(''), isFalse);
    });

    test('rejects a plain HTML page URL', () {
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://www.2embed.cc/embed/movie/155',
        ),
        isFalse,
      );
    });

    test('rejects an API/JSON endpoint URL', () {
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://vidsrc.to/api/source/155',
        ),
        isFalse,
      );
    });

    test('rejects a URL that only contains .m3u8 inside a query value', () {
      // e.g. a redirect/error page whose query mentions the playlist name.
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/error?file=master.m3u8&reason=missing',
        ),
        isFalse,
      );
    });

    test('rejects a redirect-style URL whose .m3u8 is only in the query', () {
      // Some CDNs redirect via ?to=/url — the media path is in the query
      // value, not the URL path, so it must NOT be captured as a stream.
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/redirect?to=video.m3u8',
        ),
        isFalse,
      );
      // Fragment before the extension does not rescue a non-media path.
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/redirect?to=video.m3u8#frag',
        ),
        isFalse,
      );
    });

    test('rejects a mid-path .m3u8 segment URL (a.m3u8/b.ts)', () {
      // CDN segment URLs place the playlist name mid-path. The scanner now
      // captures the WHOLE token before filtering, so this must be rejected
      // instead of matching a broken `a.m3u8` prefix.
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/hls/a.m3u8/b.ts',
        ),
        isFalse,
      );
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/hls/a.m3u8/b.ts?token=abc',
        ),
        isFalse,
      );
    });

    test('rejects a mid-path .mp4 segment URL (a.mp4/segment.ts)', () {
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/hls/a.mp4/seg-001.ts',
        ),
        isFalse,
      );
    });

    test('is case-insensitive', () {
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/hls/MASTER.M3U8',
        ),
        isTrue,
      );
      expect(
        StreamSourceDataSource.shouldCaptureUrl(
          'https://cdn.example.com/js/hls.M3U8.MIN.JS',
        ),
        isFalse,
      );
    });
  });

  group('TwoEmbedSkinExtractor (live 2embed.skin domain)', () {
    test('buildEmbedUrl uses the 2embed.skin movie path', () {
      const extractor = TwoEmbedSkinExtractor();

      expect(extractor.sourceId, 'two_embed_skin');
      expect(extractor.label, '2Embed.skin');
      expect(
        extractor.buildEmbedUrl(155),
        'https://www.2embed.skin/embed/movie/155',
      );
      expect(
        extractor.buildEmbedUrl(969681),
        'https://www.2embed.skin/embed/movie/969681',
      );
    });

    test('is registered in the SourceAggregator registry', () {
      final ids = SourceAggregator.extractors.map((e) => e.sourceId).toList();

      expect(ids, contains('two_embed_skin'));
      // Keeps both legacy 2embed.cc and the live .skin domain as separate
      // toggles so one region-blocked/rotated domain never kills the source.
      expect(ids, contains('two_embed'));
      // Registry order = reliability order (2026-08 on-device evidence): the
      // live .skin domain comes BEFORE legacy 2embed.cc, which serves
      // about:blank in some regions (white screen).
      expect(
        ids.indexOf('two_embed_skin'),
        lessThan(ids.indexOf('two_embed')),
      );
    });
  });

  group('StreamSourceDataSource.decodeHtmlEntities', () {
    test('decodes &amp; to & (the HTTP 502 class fix)', () {
      expect(
        StreamSourceDataSource.decodeHtmlEntities(
          'https://noir.cdn.store/video.mp4?sign=abc&amp;t=123&amp;headers=%7B%7D',
        ),
        'https://noir.cdn.store/video.mp4?sign=abc&t=123&headers=%7B%7D',
      );
    });

    test('decodes other named entities', () {
      // `&amp;lt` is an entity-encoded literal `&lt` (single pass leaves it
      // as text); real `&apos;`/`&nbsp;` entities DO decode.
      expect(
        StreamSourceDataSource.decodeHtmlEntities(
          'a=1&amp;lt=2&amp;gt=3&amp;quot=4',
        ),
        'a=1&lt=2&gt=3&quot=4',
      );
      expect(
        StreamSourceDataSource.decodeHtmlEntities("x&apos;y&nbsp;z"),
        "x'y z",
      );
    });

    test('decodes numeric entities (decimal and hex)', () {
      expect(
        StreamSourceDataSource.decodeHtmlEntities(
          'x&#38;y&#x26;z',
        ),
        'x&y&z',
      );
    });

    test('single pass: &amp;lt; decodes to &lt;, never to <', () {
      // A literal `&amp;lt;` represents the text `&lt;` — double decoding
      // (chained replaceAll) would wrongly produce `<`.
      expect(
        StreamSourceDataSource.decodeHtmlEntities('&amp;lt;'),
        '&lt;',
      );
    });

    test('leaves URLs without entities unchanged', () {
      const url = 'https://cdn.example.com/hls/master.m3u8?token=abc&x=1';
      expect(StreamSourceDataSource.decodeHtmlEntities(url), url);
    });

    test('leaves unknown/malformed entities unchanged', () {
      expect(
        StreamSourceDataSource.decodeHtmlEntities('a&b&c&unknown;'),
        'a&b&c&unknown;',
      );
    });

    test('decoded signed URL still passes shouldCaptureUrl', () {
      final decoded = StreamSourceDataSource.decodeHtmlEntities(
        'https://noir.cdn.store/res.mp4?sign=abc&amp;t=123',
      );
      expect(StreamSourceDataSource.shouldCaptureUrl(decoded), isTrue);
    });
  });

  group('StreamSourceDataSource.isDirectPlayableUrl', () {
    test('accepts a plain .mp4', () {
      expect(
        StreamSourceDataSource.isDirectPlayableUrl(
          'https://cdn.example.com/video.mp4',
        ),
        isTrue,
      );
    });

    test('accepts a signed URL with a FILLED headers param', () {
      // A non-empty headers= template (filled by the player) is replayable.
      expect(
        StreamSourceDataSource.isDirectPlayableUrl(
          'https://cdn.example.com/v.mp4'
          '?sign=x&headers=%7B%22Referer%22%3A%22https%3A%2F%2Fembed.example%22%7D',
        ),
        isTrue,
      );
    });

    test('REJECTS the empty headers=%7B%7D template (CDN 428 class)', () {
      // VidLink-style signed URL the player fills right before requesting;
      // replayed outside the page the CDN answers 428 Forbidden.
      expect(
        StreamSourceDataSource.isDirectPlayableUrl(
          'https://noir.example.store/mp/bt/abc.mp4'
          '?sign=deadbeef&t=1785544347'
          '&headers=%7B%7D&host=https%3A%2F%2Fcdn.example.com',
        ),
        isFalse,
      );
    });

    test('REJECTS the literal headers={} template', () {
      expect(
        StreamSourceDataSource.isDirectPlayableUrl(
          'https://cdn.example.com/v.mp4?headers={}&sign=x',
        ),
        isFalse,
      );
    });

    test('rejects script files (extension guard still applies)', () {
      expect(
        StreamSourceDataSource.isDirectPlayableUrl(
          'https://cdn.example.com/hls.m3u8.min.js',
        ),
        isFalse,
      );
    });
  });
}
