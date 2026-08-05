import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/core/network/api_client.dart';
import 'package:filmku/features/movies/data/datasources/subtitle_datasource.dart';

/// Serves canned responses keyed by request URI PATH (ignores query params).
class _FakeSubAdapter implements HttpClientAdapter {
  _FakeSubAdapter(this.responses);

  final Map<String, ResponseBody> responses;

  /// Referer header sent for each request path — lets tests assert that the
  /// .zip download carries the YIFY detail page as Referer (Cloudflare
  /// 403s it otherwise).
  final Map<String, String?> referers = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    referers[options.uri.path] = options.headers['Referer'] as String?;
    final hit = responses[options.uri.path];
    if (hit != null) return hit;
    return ResponseBody.fromString('not found', 404);
  }

  @override
  void close({bool force = false}) {}
}

const String _moviePage = '''
<html><body>
<table>
<tr><td><a href="/subtitles/spider-man-no-way-home-2021-english-yify-395000">English</a></td></tr>
<tr><td><a href="/subtitles/spider-man-no-way-home-2021-indonesian-yify-395314">Indonesian</a></td></tr>
<tr><td><a href="/subtitles/spider-man-no-way-home-2021-indonesian-yify-395315">Indonesian</a></td></tr>
<tr><td><a href="/subtitles/spider-man-no-way-home-2021-arabic-yify-395289">Arabic</a></td></tr>
</table>
</body></html>
''';

const String _detailPage = '''
<html><body>
<a class="btn-icon download-subtitle" href="/subtitle/spider-man-no-way-home-2021-indonesian-yify-395314.zip">Download</a>
</body></html>
''';

const String _srtContent =
    '1\n00:00:00,500 --> 00:00:02,000\nHalo dunia, ini teks.\n\n';

Uint8List _buildZip() {
  final archive = Archive();
  archive.addFile(ArchiveFile.string(
    'Spider.Man.No.Way.Home.2021.srt',
    _srtContent,
  ));
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  group('SubtitleDatasource parsers', () {
    test('parseSubtitleLinks detects languages and dedupes paths', () {
      final links = SubtitleDatasource.parseSubtitleLinks(_moviePage);
      expect(links.length, 4);
      final indo = links.where((l) => l.language == 'id').toList();
      expect(indo.length, 2);
      expect(indo.first.label, 'Indonesian');
      final en = links.firstWhere((l) => l.language == 'en');
      expect(en.label, 'English');
      final ar = links.firstWhere((l) => l.language == 'ar');
      expect(ar.label, 'Arabic');
    });

    test('parseSubtitleLinks ignores non-subtitle links', () {
      final links = SubtitleDatasource.parseSubtitleLinks(
        '<a href="/subtitles/foo">x</a><a href="/movies/1">y</a>'
        '<a href="/subtitles/some-movie-2021-english-yify-123">English</a>',
      );
      expect(links.length, 1);
      expect(links.first.language, 'en');
    });

    test('parseSubtitleLinks ignores navigation links without -yify-{id}', () {
      final links = SubtitleDatasource.parseSubtitleLinks(
        '<a href="/subtitles/popular">Popular</a>'
        '<a href="/subtitles/browse/2">Page 2</a>'
        '<a href="/subtitles/spider-man-2021-indonesian-yify-395314">'
        'Indonesian</a>',
      );
      expect(links.length, 1);
      expect(links.first.language, 'id');
    });

    test('parseZipLink extracts the .zip download path', () {
      expect(
        SubtitleDatasource.parseZipLink(_detailPage),
        '/subtitle/spider-man-no-way-home-2021-indonesian-yify-395314.zip',
      );
    });

    test('parseZipLink returns null without a zip link', () {
      expect(SubtitleDatasource.parseZipLink('<html>no link</html>'), isNull);
    });

    test('extractSrtFromZip returns the SRT text', () {
      final srt = SubtitleDatasource.extractSrtFromZip(_buildZip());
      expect(srt, _srtContent);
    });

    test('extractSrtFromZip returns null for garbage bytes', () {
      expect(SubtitleDatasource.extractSrtFromZip([1, 2, 3, 4]), isNull);
    });

    test('extractSrtFromZip fallback picks the largest text file', () {
      final archive = Archive();
      archive.addFile(ArchiveFile.string('readme.nfo', 'tiny readme'));
      archive.addFile(
        ArchiveFile.string('subtitle', '$_srtContent$_srtContent'),
      );
      final zip = Uint8List.fromList(ZipEncoder().encode(archive)!);
      expect(
        SubtitleDatasource.extractSrtFromZip(zip),
        '$_srtContent$_srtContent',
      );
    });

    test('extractSrtFromZip strips a UTF-8 BOM', () {
      final archive = Archive();
      archive.addFile(ArchiveFile.string(
        'sub.srt',
        '\uFEFF$_srtContent',
      ));
      final zip = Uint8List.fromList(ZipEncoder().encode(archive)!);
      expect(SubtitleDatasource.extractSrtFromZip(zip), _srtContent);
    });
  });

  group('SubtitleDatasource.fetchSubtitle', () {
    (SubtitleDatasource, _FakeSubAdapter, _FakeSubAdapter) build(
      Map<String, ResponseBody> tmdbResponses,
      Map<String, ResponseBody> yifyResponses,
    ) {
      final tmdbDio = Dio()..httpClientAdapter = _FakeSubAdapter(tmdbResponses);
      // The real datasource's Dio uses ResponseType.bytes for the HTML/zip
      // fetches — the injected dio must match or dio's default JSON
      // transformer will try to decode the HTML as JSON and throw.
      final yifyDio = Dio(
        BaseOptions(responseType: ResponseType.bytes),
      )..httpClientAdapter = _FakeSubAdapter(yifyResponses);
      final ds =
          SubtitleDatasource(tmdb: ApiClient(dio: tmdbDio), dio: yifyDio);
      return (
        ds,
        tmdbDio.httpClientAdapter as _FakeSubAdapter,
        yifyDio.httpClientAdapter as _FakeSubAdapter
      );
    }

    test('fetches the Indonesian subtitle (preferred over English)', () async {
      final (ds, _, _) = build(
        {
          '/movie/315162/external_ids': ResponseBody.fromString(
            '{"imdb_id":"tt10872600"}',
            200,
            headers: {
              'content-type': ['application/json']
            },
          ),
        },
        {
          '/movie-imdb/tt10872600':
              ResponseBody.fromBytes(utf8.encode(_moviePage), 200),
          '/subtitles/spider-man-no-way-home-2021-indonesian-yify-395314':
              ResponseBody.fromBytes(utf8.encode(_detailPage), 200),
          '/subtitle/spider-man-no-way-home-2021-indonesian-yify-395314.zip':
              ResponseBody.fromBytes(_buildZip(), 200),
        },
      );
      final sub = await ds.fetchSubtitle(315162);
      expect(sub, isNotNull);
      expect(sub!.language, 'id');
      expect(sub.title, 'Indonesian');
      expect(sub.data, _srtContent);
    });

    test('returns null when TMDB has no imdb_id', () async {
      final (ds, _, _) = build(
        {
          '/movie/1234/external_ids': ResponseBody.fromString(
            '{"id":1234}',
            200,
            headers: {
              'content-type': ['application/json']
            },
          ),
        },
        {},
      );
      expect(await ds.fetchSubtitle(1234), isNull);
    });

    test('returns null when YIFY has no subtitle for the movie', () async {
      final (ds, _, _) = build(
        {
          '/movie/1/external_ids': ResponseBody.fromString(
            '{"imdb_id":"tt0000001"}',
            200,
            headers: {
              'content-type': ['application/json']
            },
          ),
        },
        {
          '/movie-imdb/tt0000001':
              ResponseBody.fromString('<html>no subtitles listed</html>', 200),
        },
      );
      expect(await ds.fetchSubtitle(1), isNull);
    });

    test('returns null when the TMDB call errors', () async {
      final (ds, _, _) = build(
        {
          '/movie/999/external_ids': ResponseBody.fromString('oops', 500),
        },
        {},
      );
      expect(await ds.fetchSubtitle(999), isNull);
    });

    test('zip download sends the YIFY detail page as Referer', () async {
      final (ds, _, yify) = build(
        {
          '/movie/315162/external_ids': ResponseBody.fromString(
            '{"imdb_id":"tt10872600"}',
            200,
            headers: {
              'content-type': ['application/json']
            },
          ),
        },
        {
          '/movie-imdb/tt10872600':
              ResponseBody.fromBytes(utf8.encode(_moviePage), 200),
          '/subtitles/spider-man-no-way-home-2021-indonesian-yify-395314':
              ResponseBody.fromBytes(utf8.encode(_detailPage), 200),
          '/subtitle/spider-man-no-way-home-2021-indonesian-yify-395314.zip':
              ResponseBody.fromBytes(_buildZip(), 200),
        },
      );
      final sub = await ds.fetchSubtitle(315162);
      expect(sub, isNotNull);
      // The Referer must be the subtitle DETAIL page (what a browser sends
      // when clicking Download) — Cloudflare rejects the zip without it.
      expect(
        yify.referers[
            '/subtitle/spider-man-no-way-home-2021-indonesian-yify-395314.zip'],
        'https://yifysubtitles.ch'
        '/subtitles/spider-man-no-way-home-2021-indonesian-yify-395314',
      );
    });

    test('falls back to English when no Indonesian subtitle exists', () async {
      const enPage = '''
<html><body>
<a href="/subtitles/old-movie-1960-english-yify-999">English</a>
</body></html>
''';
      const enDetail = '''
<a class="download-subtitle" href="/subtitle/old-movie-1960-english-yify-999.zip">Download</a>
''';
      final (ds, _, _) = build(
        {
          '/movie/77/external_ids': ResponseBody.fromString(
            '{"imdb_id":"tt0000077"}',
            200,
            headers: {
              'content-type': ['application/json']
            },
          ),
        },
        {
          '/movie-imdb/tt0000077':
              ResponseBody.fromBytes(utf8.encode(enPage), 200),
          '/subtitles/old-movie-1960-english-yify-999':
              ResponseBody.fromBytes(utf8.encode(enDetail), 200),
          '/subtitle/old-movie-1960-english-yify-999.zip':
              ResponseBody.fromBytes(_buildZip(), 200),
        },
      );
      final sub = await ds.fetchSubtitle(77);
      expect(sub, isNotNull);
      expect(sub!.language, 'en');
    });
  });
}
