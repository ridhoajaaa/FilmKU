import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/features/movies/data/datasources/stream_source_datasource.dart';
import 'package:filmku/features/movies/domain/entities/video_source.dart';

/// Unit tests for the VidNest native extraction (v1.3.24).
///
/// The 2Embed vnest chain (shell → streamsrcs.2embed.cc/vnest → cineby.hair →
/// VidNest) was previously considered browser-only. VidNest's server API
/// (`new.vidnest.fun/{server}/movie/{tmdb}`) returns `{"data":"<encoded>",
/// "encrypted":true}` where the payload is a base64 variant over a CUSTOM
/// 64-char alphabet. Decoding it yields the stream JSON, which carries the
/// exact `Referer` the CDN requires (goodstream.cc: 403 without, 200 with —
/// verified 2026-08).
void main() {
  const alphabet = StreamSourceDataSource.vidNestAlphabet;

  /// Encodes [text] with the VidNest custom-alphabet base64 (inverse of
  /// [StreamSourceDataSource.decodeVidNestPayload]) so fixtures stay
  /// readable and the decoder round-trips exactly. Pads with '='.
  String encodeVidNest(String text) {
    final bytes = utf8.encode(text);
    final out = StringBuffer();
    for (var i = 0; i < bytes.length; i += 3) {
      final b0 = bytes[i];
      final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
      final v0 = b0 >> 2;
      final v1 = ((b0 & 3) << 4) | (b1 >> 4);
      final v2 = ((b1 & 15) << 2) | (b2 >> 6);
      final v3 = b2 & 63;
      out.writeCharCode(alphabet.codeUnitAt(v0));
      out.writeCharCode(alphabet.codeUnitAt(v1));
      out.writeCharCode(
          i + 1 < bytes.length ? alphabet.codeUnitAt(v2) : 61); // '='
      out.writeCharCode(
          i + 2 < bytes.length ? alphabet.codeUnitAt(v3) : 61); // '='
    }
    return out.toString();
  }

  /// Encodes [text] WITHOUT trailing padding — a non-multiple-of-4 input the
  /// decoder must still handle (the site pads each group with '=' itself).
  String encodeVidNestNoPad(String text) {
    final padded = encodeVidNest(text);
    return padded.replaceAll(RegExp(r'=+$'), '');
  }

  group('StreamSourceDataSource.decodeVidNestPayload', () {
    test('round-trips arbitrary JSON through the custom alphabet', () {
      const plain = '{"streams":[{"type":"hls","url":"https://cdn/x.m3u8"}]}';
      expect(StreamSourceDataSource.decodeVidNestPayload(encodeVidNest(plain)),
          plain);
    });

    test('round-trips non-multiple-of-3 byte lengths (padding)', () {
      for (final plain in ['a', 'ab', 'abc', 'abcd', 'hello world']) {
        expect(
          StreamSourceDataSource.decodeVidNestPayload(encodeVidNest(plain)),
          plain,
          reason: 'round-trip failed for $plain',
        );
      }
    });

    test('decodes unpadded (non-multiple-of-4) input like the site', () {
      // 2 bytes encoded without the trailing padding char — the site pads
      // the group with '=' itself before decoding, so 'ab' must survive.
      expect(
        StreamSourceDataSource.decodeVidNestPayload(encodeVidNestNoPad('ab')),
        'ab',
      );
      expect(
        StreamSourceDataSource.decodeVidNestPayload(
            encodeVidNestNoPad('hello world')),
        'hello world',
      );
    });

    test('the alphabet is 64 data chars plus the = padding marker', () {
      // 62 alphanumerics + '/' + '+' followed by '=' — the padding marker is
      // part of the source's alphabet string and maps to the 64 sentinel.
      expect(StreamSourceDataSource.vidNestAlphabet.length, 65);
      expect(StreamSourceDataSource.vidNestAlphabet[64], '=');
      expect(
        RegExp(r'^[A-Za-z0-9+/]{64}=$')
            .hasMatch(StreamSourceDataSource.vidNestAlphabet),
        isTrue,
      );
    });

    test('returns null for empty input', () {
      expect(StreamSourceDataSource.decodeVidNestPayload(''), isNull);
    });

    test('returns null for a payload with no decodable data', () {
      // All padding — every byte emission is suppressed.
      expect(StreamSourceDataSource.decodeVidNestPayload('===='), isNull);
    });
  });

  group('StreamSourceDataSource.vidNestCandidates', () {
    test('picks the first HLS stream and carries its Referer header', () {
      final response = <String, dynamic>{
        'data': encodeVidNest(
          '{"streams":['
          '{"type":"mp4","language":"MAIN",'
          '"url":"https://hlmv.cdn.example/videos/abc",'
          '"headers":{"Referer":"https://goodstream.cc/embed/abc"}},'
          '{"type":"hls","language":"GS-25",'
          '"url":"https://goodstream.cc/pl/abc/0-12?e=token123",'
          '"headers":{"Referer":"https://goodstream.cc/embed/abc"}}'
          '],"totalLanguages":2}',
        ),
        'encrypted': true,
      };

      final candidates = StreamSourceDataSource.vidNestCandidates(
        response,
        sourceId: 'two_embed_skin',
        label: '2Embed.skin',
        embedUrl: 'https://www.2embed.skin/embed/movie/634649',
      );

      expect(candidates, isNotEmpty);
      final source = candidates.first;
      expect(source.videoUrl, 'https://goodstream.cc/pl/abc/0-12?e=token123');
      expect(source.sourceId, 'two_embed_skin');
      expect(source.embedUrl, 'https://www.2embed.skin/embed/movie/634649');
      expect(
        source.httpHeaders,
        {'Referer': 'https://goodstream.cc/embed/abc'},
      );
    });

    test('returns every stream, HLS first, each with its own headers', () {
      final response = <String, dynamic>{
        'data': encodeVidNest(
          '{"streams":['
          '{"type":"mp4","url":"https://hlmv.cdn/v/abc",'
          '"headers":{"Referer":"https://goodstream.cc/embed/abc"}},'
          '{"type":"hls","url":"https://goodstream.cc/pl/a/1?e=1",'
          '"headers":{"Referer":"https://goodstream.cc/embed/abc"}},'
          '{"type":"hls","url":"https://goodstream.cc/streamsvr/a/1?e=2",'
          '"headers":{"Referer":"https://goodstream.cc/embed/abc"}}'
          ']}',
        ),
        'encrypted': true,
      };

      final candidates = StreamSourceDataSource.vidNestCandidates(
        response,
        sourceId: 'two_embed_skin',
        label: '2Embed.skin',
        embedUrl: 'https://www.2embed.skin/embed/movie/634649',
      );

      expect(candidates, hasLength(3));
      // HLS streams first (the mp4 MAIN stream is Cloudflare-451 outside a
      // real browser), then the mp4.
      expect(candidates[0].videoUrl, 'https://goodstream.cc/pl/a/1?e=1');
      expect(candidates[1].videoUrl, 'https://goodstream.cc/streamsvr/a/1?e=2');
      expect(candidates[2].videoUrl, 'https://hlmv.cdn/v/abc');
      for (final c in candidates) {
        expect(c.httpHeaders, {'Referer': 'https://goodstream.cc/embed/abc'});
      }
    });

    test('falls back to the mp4 when the payload has no HLS stream', () {
      final response = <String, dynamic>{
        'data': encodeVidNest(
          '{"streams":[{"type":"mp4","url":"https://cdn.example/v.mp4",'
          '"headers":{"Referer":"https://embed.example/"}}]}',
        ),
        'encrypted': true,
      };

      final candidates = StreamSourceDataSource.vidNestCandidates(
        response,
        sourceId: 'two_embed_skin',
        label: '2Embed.skin',
        embedUrl: 'https://www.2embed.skin/embed/movie/155',
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.videoUrl, 'https://cdn.example/v.mp4');
      expect(
          candidates.single.httpHeaders, {'Referer': 'https://embed.example/'});
    });

    test('returns empty when the payload decodes to a non-object', () {
      final response = <String, dynamic>{
        'data': encodeVidNest('"just a string"'),
        'encrypted': true,
      };

      expect(
        StreamSourceDataSource.vidNestCandidates(
          response,
          sourceId: 'two_embed_skin',
          label: '2Embed.skin',
          embedUrl: 'https://www.2embed.skin/embed/movie/155',
        ),
        isEmpty,
      );
    });

    test('returns empty when the payload has no streams array', () {
      final response = <String, dynamic>{
        'data': encodeVidNest('{"totalLanguages":0}'),
        'encrypted': true,
      };

      expect(
        StreamSourceDataSource.vidNestCandidates(
          response,
          sourceId: 'two_embed_skin',
          label: '2Embed.skin',
          embedUrl: 'https://www.2embed.skin/embed/movie/155',
        ),
        isEmpty,
      );
    });

    test('returns empty when the data field is missing or unencrypted', () {
      expect(
        StreamSourceDataSource.vidNestCandidates(
          const <String, dynamic>{},
          sourceId: 'two_embed_skin',
          label: '2Embed.skin',
          embedUrl: 'https://www.2embed.skin/embed/movie/155',
        ),
        isEmpty,
      );
      expect(
        StreamSourceDataSource.vidNestCandidates(
          const <String, dynamic>{'data': 42},
          sourceId: 'two_embed_skin',
          label: '2Embed.skin',
          embedUrl: 'https://www.2embed.skin/embed/movie/155',
        ),
        isEmpty,
      );
    });

    test('ignores a stream with an empty url', () {
      final response = <String, dynamic>{
        'data': encodeVidNest(
          '{"streams":[{"type":"hls","url":""}]}',
        ),
        'encrypted': true,
      };

      expect(
        StreamSourceDataSource.vidNestCandidates(
          response,
          sourceId: 'two_embed_skin',
          label: '2Embed.skin',
          embedUrl: 'https://www.2embed.skin/embed/movie/155',
        ),
        isEmpty,
      );
    });

    test('drops streams with missing urls but keeps valid ones', () {
      final response = <String, dynamic>{
        'data': encodeVidNest(
          '{"streams":['
          '{"type":"hls","url":""},'
          '{"type":"hls"},'
          '{"type":"hls","url":"https://goodstream.cc/pl/x/1?e=9"}'
          ']}',
        ),
        'encrypted': true,
      };

      final candidates = StreamSourceDataSource.vidNestCandidates(
        response,
        sourceId: 'two_embed_skin',
        label: '2Embed.skin',
        embedUrl: 'https://www.2embed.skin/embed/movie/155',
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.videoUrl, 'https://goodstream.cc/pl/x/1?e=9');
    });
  });

  group('VideoSource httpHeaders', () {
    test('defaults to an empty map', () {
      const source = VideoSource(sourceId: 'x', label: 'X');
      expect(source.httpHeaders, isEmpty);
      expect(source.isPlayable, isFalse);
    });

    test('copyWith replaces headers', () {
      const source = VideoSource(sourceId: 'x', label: 'X');
      final withHeaders = source.copyWith(
        httpHeaders: const {'Referer': 'https://cdn.example/'},
      );
      expect(withHeaders.httpHeaders, {'Referer': 'https://cdn.example/'});
      // The original is untouched (immutable entity).
      expect(source.httpHeaders, isEmpty);
    });
  });

  group('StreamSourceDataSource.vidNestServers', () {
    test('lists the known server API endpoints in probe order', () {
      expect(StreamSourceDataSource.vidNestServers, isNotEmpty);
      expect(StreamSourceDataSource.vidNestServers.first, 'hollymoviehd');
    });
  });
}
