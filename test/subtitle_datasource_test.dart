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

  /// Every request path this adapter served — lets tests assert that the
  /// keyless metadata path makes NO TMDB request at all.
  final List<String> hits = [];

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
    hits.add(options.uri.path);
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

// --- SubtitleCat fixtures ---

const String _scSearchPage = '''
<html><body>
<a href="subs/1532/Spider-Man-No-Way-Home-2021-1080p-YTS.html">1</a>
<a href="subs/335/Spider-Man-No-Way-Home-2021-HDTC-STAGATV.html">2</a>
<a href="/somewhere/else.html">nav</a>
</body></html>
''';

const String _scDetailPage = '''
<html><body>
<a href="/subs/1546/Spider-Man-No-Way-Home-2021-en.srt">English</a>
<a href="/subs/1582/Spider-Man-No-Way-Home-2021-id.srt">Indonesian</a>
<a href="/subs/1588/Spider-Man-No-Way-Home-2021-es-419.srt">Spanish</a>
</body></html>
''';

const String _scDetailEnglishOnly = '''
<html><body>
<a href="/subs/1546/Spider-Man-No-Way-Home-2021-en.srt">English</a>
</body></html>
''';

const String _scSrtContent =
    '1\n00:00:01,000 --> 00:00:03,000\nSubtitle Indonesia dari SubtitleCat.\n\n';

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

    test('parseSubtitleCatSlugs extracts release-group slugs only', () {
      final slugs = SubtitleDatasource.parseSubtitleCatSlugs(_scSearchPage);
      expect(slugs.length, 2);
      expect(
        slugs.first,
        'subs/1532/Spider-Man-No-Way-Home-2021-1080p-YTS.html',
      );
      expect(
          slugs.last, 'subs/335/Spider-Man-No-Way-Home-2021-HDTC-STAGATV.html');
    });

    test('parseSubtitleCatSrtLinks decodes languages from filename suffixes',
        () {
      final links = SubtitleDatasource.parseSubtitleCatSrtLinks(_scDetailPage);
      expect(links.length, 3);
      final indo = links.firstWhere((l) => l.language == 'id');
      expect(indo.label, 'Indonesian');
      expect(indo.path, '/subs/1582/Spider-Man-No-Way-Home-2021-id.srt');
      expect(links.firstWhere((l) => l.language == 'en').label, 'English');
      expect(
        links.firstWhere((l) => l.language == 'es-419').label,
        'Spanish (Latin America)',
      );
    });

    test('parseSubtitleCatSrtLinks keeps paths with unknown suffixes', () {
      const html = '''
<a href="/subs/999/Some.Movie.2021.part1.srt">part</a>
''';
      final links = SubtitleDatasource.parseSubtitleCatSrtLinks(html);
      expect(links.length, 1);
      expect(links.first.language, 'xx');
      expect(links.first.path, '/subs/999/Some.Movie.2021.part1.srt');
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

    test('falls back to SubtitleCat when YIFY has no subtitle (Indonesian)',
        () async {
      final (ds, _, _) = build(
        {
          '/movie/315162': ResponseBody.fromString(
            '{"title":"Spider-Man: No Way Home",'
            '"release_date":"2021-12-15"}',
            200,
            headers: {
              'content-type': ['application/json']
            },
          ),
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
              ResponseBody.fromString('<html>no subtitles listed</html>', 200),
          // SubtitleCat chain: search page → detail page → -id.srt
          '/index.php': ResponseBody.fromBytes(utf8.encode(_scSearchPage), 200),
          '/subs/1532/Spider-Man-No-Way-Home-2021-1080p-YTS.html':
              ResponseBody.fromBytes(utf8.encode(_scDetailPage), 200),
          '/subs/1582/Spider-Man-No-Way-Home-2021-id.srt':
              ResponseBody.fromBytes(utf8.encode(_scSrtContent), 200),
        },
      );
      final sub = await ds.fetchSubtitle(315162);
      expect(sub, isNotNull);
      expect(sub!.language, 'id');
      expect(sub.title, 'Indonesian');
      expect(sub.data, _scSrtContent);
    });

    test('SubtitleCat works without an IMDB id (title-only search)', () async {
      final (ds, _, _) = build(
        {
          '/movie/1234': ResponseBody.fromString(
            '{"title":"Puss in Boots: The Last Wish",'
            '"release_date":"2022-12-07"}',
            200,
            headers: {
              'content-type': ['application/json']
            },
          ),
          '/movie/1234/external_ids': ResponseBody.fromString(
            '{"id":1234}',
            200,
            headers: {
              'content-type': ['application/json']
            },
          ),
        },
        {
          '/index.php': ResponseBody.fromBytes(utf8.encode(_scSearchPage), 200),
          '/subs/1532/Spider-Man-No-Way-Home-2021-1080p-YTS.html':
              ResponseBody.fromBytes(utf8.encode(_scDetailPage), 200),
          '/subs/1582/Spider-Man-No-Way-Home-2021-id.srt':
              ResponseBody.fromBytes(utf8.encode(_scSrtContent), 200),
        },
      );
      final sub = await ds.fetchSubtitle(1234);
      expect(sub, isNotNull);
      expect(sub!.language, 'id');
    });

    test('SubtitleCat falls back to English when no Indonesian exists',
        () async {
      final (ds, _, _) = build(
        {
          '/movie/77': ResponseBody.fromString(
            '{"title":"Old Movie","release_date":"1960-01-01"}',
            200,
            headers: {
              'content-type': ['application/json']
            },
          ),
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
              ResponseBody.fromString('<html>no subtitles listed</html>', 200),
          '/index.php': ResponseBody.fromBytes(utf8.encode(_scSearchPage), 200),
          '/subs/1532/Spider-Man-No-Way-Home-2021-1080p-YTS.html':
              ResponseBody.fromBytes(utf8.encode(_scDetailEnglishOnly), 200),
          '/subs/1546/Spider-Man-No-Way-Home-2021-en.srt':
              ResponseBody.fromBytes(utf8.encode(_scSrtContent), 200),
        },
      );
      final sub = await ds.fetchSubtitle(77);
      expect(sub, isNotNull);
      expect(sub!.language, 'en');
      expect(sub.title, 'English');
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

  group('SubtitleDatasource.fetchSubtitleFromMeta (keyless metadata path)', () {
    (SubtitleDatasource, _FakeSubAdapter, _FakeSubAdapter) buildKeyless(
      Map<String, ResponseBody> yifyResponses,
    ) {
      // TMDB adapter starts EMPTY — any TMDB request would 404 and the test
      // asserts NONE happened (the metadata path must be keyless).
      final tmdbDio = Dio()..httpClientAdapter = _FakeSubAdapter({});
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

    test('title+year drives SubtitleCat with NO TMDB request at all', () async {
      final (ds, tmdb, _) = buildKeyless({
        '/index.php': ResponseBody.fromBytes(utf8.encode(_scSearchPage), 200),
        '/subs/1532/Spider-Man-No-Way-Home-2021-1080p-YTS.html':
            ResponseBody.fromBytes(utf8.encode(_scDetailPage), 200),
        '/subs/1582/Spider-Man-No-Way-Home-2021-id.srt':
            ResponseBody.fromBytes(utf8.encode(_scSrtContent), 200),
      });
      final sub = await ds.fetchSubtitleFromMeta(
        title: 'Spider-Man: No Way Home',
        year: '2021',
      );
      expect(sub, isNotNull);
      expect(sub!.language, 'id');
      expect(sub.title, 'Indonesian');
      expect(sub.data, _scSrtContent);
      // The whole point of the metadata path: NO TMDB request.
      expect(tmdb.hits, isEmpty);
    });

    test('title alone (no year) still reaches SubtitleCat', () async {
      final (ds, tmdb, _) = buildKeyless({
        '/index.php': ResponseBody.fromBytes(utf8.encode(_scSearchPage), 200),
        '/subs/1532/Spider-Man-No-Way-Home-2021-1080p-YTS.html':
            ResponseBody.fromBytes(utf8.encode(_scDetailPage), 200),
        '/subs/1582/Spider-Man-No-Way-Home-2021-id.srt':
            ResponseBody.fromBytes(utf8.encode(_scSrtContent), 200),
      });
      final sub = await ds.fetchSubtitleFromMeta(title: 'Spider-Man');
      expect(sub, isNotNull);
      expect(sub!.language, 'id');
      expect(tmdb.hits, isEmpty);
    });

    test('a passed imdbId drives YIFY with NO TMDB request', () async {
      final (ds, tmdb, _) = buildKeyless({
        '/movie-imdb/tt10872600':
            ResponseBody.fromBytes(utf8.encode(_moviePage), 200),
        '/subtitles/spider-man-no-way-home-2021-indonesian-yify-395314':
            ResponseBody.fromBytes(utf8.encode(_detailPage), 200),
        '/subtitle/spider-man-no-way-home-2021-indonesian-yify-395314.zip':
            ResponseBody.fromBytes(_buildZip(), 200),
      });
      final sub = await ds.fetchSubtitleFromMeta(imdbId: 'tt10872600');
      expect(sub, isNotNull);
      expect(sub!.language, 'id');
      expect(tmdb.hits, isEmpty);
    });

    test('returns null when nothing is passed and no provider answers',
        () async {
      final (ds, _, _) = buildKeyless({});
      expect(await ds.fetchSubtitleFromMeta(), isNull);
    });
  });
}
