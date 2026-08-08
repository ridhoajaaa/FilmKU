import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/core/network/api_client.dart';
import 'package:filmku/features/movies/data/datasources/subtitle_datasource.dart';

/// Serves canned responses keyed by request URI PATH (ignores query params).
class _FakeSubAdapter implements HttpClientAdapter {
  _FakeSubAdapter(
    this.responses, {
    this.throwing = const <String>{},
    this.hanging = const <String>{},
  });

  final Map<String, ResponseBody> responses;

  /// Paths that simulate a hard network failure (DioException) — e.g. the
  /// Cloudflare-protected YIFY chain failing on-device. Lets tests prove one
  /// source failing can never cancel the other parallel source.
  final Set<String> throwing;

  /// Paths that NEVER complete — simulates a hung source. Lets tests prove
  /// the per-source timeout bounds a hung YIFY chain so SubtitleCat's result
  /// still wins.
  final Set<String> hanging;

  /// Every request path this adapter served — lets tests assert that the
  /// keyless metadata path makes NO TMDB request at all.
  final List<String> hits = [];

  /// Referer header sent for each request path — lets tests assert that the
  /// .zip download carries the YIFY detail page as Referer (Cloudflare
  /// 403s it otherwise).
  final Map<String, String?> referers = {};

  /// Authorization header sent for each request path — lets tests assert the
  /// subdl Bearer auth reaches BOTH the search and the download (subdl 403s
  /// without it, same class of bug as the YIFY Referer).
  final Map<String, String?> authorizations = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    hits.add(options.uri.path);
    referers[options.uri.path] = options.headers['Referer'] as String?;
    authorizations[options.uri.path] =
        options.headers['Authorization'] as String?;
    if (throwing.contains(options.uri.path)) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'simulated CDN failure',
      );
    }
    if (hanging.contains(options.uri.path)) {
      // Never completes — exactly like a server that never answers (the
      // async flattening of `return Future.never` is not available here).
      return Completer<ResponseBody>().future;
    }
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

    test('parseSubdlSearchResponse parses the documented v2 response', () {
      const json = '''
{"status":true,"subtitles":[
  {"n_id":"sd-abc","release_name":"Spider.Man.2021.1080p.WEB.x264",
   "lang":"english","match_score":0.95,"url":"..."},
  {"n_id":"sd-xyz","release_name":"Spider.Man.2021.720p.BluRay.x264",
   "lang":"indonesian","match_score":0.9,"url":"..."}
]}
''';
      final entries = SubtitleDatasource.parseSubdlSearchResponse(json);
      expect(entries.length, 2);
      expect(entries.first.nId, 'sd-abc');
      expect(entries.first.language, 'en');
      expect(entries.first.label, 'English');
      expect(entries.first.releaseName, 'Spider.Man.2021.1080p.WEB.x264');
      expect(entries.last.language, 'id');
      expect(entries.last.label, 'Indonesian');
    });

    test('parseSubdlSearchResponse normalizes language codes and names', () {
      const json = '''
{"subtitles":[
  {"n_id":"1","lang":"id"},
  {"n_id":"2","lang":"indonesian"},
  {"n_id":"3","lang":"en"},
  {"n_id":"4","lang":"english"},
  {"n_id":"5","lang":"spanish"}
]}
''';
      final entries = SubtitleDatasource.parseSubdlSearchResponse(json);
      expect(entries.map((e) => e.language).toList(),
          ['id', 'id', 'en', 'en', 'es']);
    });

    test('parseSubdlSearchResponse skips entries without an n_id', () {
      const json = '''
{"subtitles":[
  {"release_name":"no id here","lang":"english"},
  {"n_id":"sd-ok","lang":"indonesian"}
]}
''';
      final entries = SubtitleDatasource.parseSubdlSearchResponse(json);
      expect(entries.length, 1);
      expect(entries.single.nId, 'sd-ok');
      expect(entries.single.language, 'id');
    });

    test('parseSubdlSearchResponse tolerates garbage and missing lists', () {
      expect(
        SubtitleDatasource.parseSubdlSearchResponse('not json at all'),
        isEmpty,
      );
      expect(
        SubtitleDatasource.parseSubdlSearchResponse('{"status":true}'),
        isEmpty,
      );
      expect(
        SubtitleDatasource.parseSubdlSearchResponse('{"subtitles":"nope"}'),
        isEmpty,
      );
    });
  });

  group('SubtitleDatasource subdl chain (third source)', () {
    (SubtitleDatasource, _FakeSubAdapter) buildSubdl(
      Map<String, ResponseBody> responses, {
      String key = 'test-key',
      Set<String> throwing = const <String>{},
    }) {
      final dio = Dio(
        BaseOptions(responseType: ResponseType.bytes),
      )..httpClientAdapter = _FakeSubAdapter(responses, throwing: throwing);
      final ds = SubtitleDatasource(
        tmdb: ApiClient(dio: Dio()..httpClientAdapter = _FakeSubAdapter({})),
        dio: dio,
        subdlApiKey: key,
        // Tight budgets so a broken subdl can never stall the test.
        subdlTimeout: const Duration(seconds: 5),
      );
      return (
        ds,
        dio.httpClientAdapter as _FakeSubAdapter,
      );
    }

    const subdlSearchJson = '''
{"status":true,"subtitles":[
  {"n_id":"sd-abc","release_name":"Spider.Man.2021.1080p.WEB.x264",
   "lang":"english","match_score":0.95},
  {"n_id":"sd-xyz","release_name":"Spider.Man.2021.720p.BluRay.x264",
   "lang":"indonesian","match_score":0.9}
]}
''';

    test('fetches Indonesian via search + format=file download', () async {
      final (ds, adapter) = buildSubdl({
        '/api/v2/subtitles/search':
            ResponseBody.fromBytes(utf8.encode(subdlSearchJson), 200),
        '/api/v2/subtitles/sd-xyz/download':
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
      // The Bearer auth must reach BOTH requests (subdl 403s without it).
      expect(adapter.authorizations['/api/v2/subtitles/search'],
          'Bearer test-key');
      expect(adapter.authorizations['/api/v2/subtitles/sd-xyz/download'],
          'Bearer test-key');
    });

    test('downloads via tmdb_id when no imdb is known', () async {
      final (ds, adapter) = buildSubdl({
        '/api/v2/subtitles/search':
            ResponseBody.fromBytes(utf8.encode(subdlSearchJson), 200),
        '/api/v2/subtitles/sd-xyz/download':
            ResponseBody.fromBytes(utf8.encode(_scSrtContent), 200),
      });
      final sub = await ds.fetchSubtitleFromMeta(tmdbId: 315162);
      expect(sub, isNotNull);
      expect(sub!.language, 'id');
      // tmdb_id + type=movie must be in the query (the fake keys by path
      // only, so assert via the hits — the search path WAS hit).
      expect(adapter.hits, contains('/api/v2/subtitles/search'));
      expect(adapter.hits, contains('/api/v2/subtitles/sd-xyz/download'));
    });

    test('no key = the subdl chain makes NO requests and returns null',
        () async {
      final (ds, adapter) = buildSubdl({}, key: '');
      final sub = await ds.fetchSubtitleFromMeta(
        title: 'Spider-Man',
        year: '2021',
      );
      expect(sub, isNull);
      // YIFY/SubtitleCat still ran (they share the dio) — assert only that
      // NO subdl endpoint was touched.
      expect(
        adapter.hits.where((p) => p.startsWith('/api/v2/subtitles')),
        isEmpty,
      );
    });

    test('a failing subdl chain returns null and never breaks the others',
        () async {
      final (ds, _) = buildSubdl(
        {},
        throwing: {'/api/v2/subtitles/search'},
      );
      final sub = await ds.fetchSubtitleFromMeta(
        title: 'Spider-Man',
        year: '2021',
      );
      expect(sub, isNull);
    });

    test('handles a zip response from format=file defensively', () async {
      final (ds, _) = buildSubdl({
        '/api/v2/subtitles/search':
            ResponseBody.fromBytes(utf8.encode(subdlSearchJson), 200),
        // Some releases only exist as an archive — the API may return zip
        // bytes even for format=file.
        '/api/v2/subtitles/sd-xyz/download':
            ResponseBody.fromBytes(_buildZip(), 200),
      });
      final sub = await ds.fetchSubtitleFromMeta(
        title: 'Spider-Man',
        year: '2021',
      );
      expect(sub, isNotNull);
      expect(sub!.language, 'id');
      expect(sub.data, _srtContent);
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
      Map<String, ResponseBody> yifyResponses, {
      Set<String> throwing = const <String>{},
      Set<String> hanging = const <String>{},
      Duration? yifyTimeout,
      Duration? subcatTimeout,
    }) {
      // TMDB adapter starts EMPTY — any TMDB request would 404 and the test
      // asserts NONE happened (the metadata path must be keyless).
      final tmdbDio = Dio()..httpClientAdapter = _FakeSubAdapter({});
      final yifyDio = Dio(
        BaseOptions(responseType: ResponseType.bytes),
      )..httpClientAdapter =
          _FakeSubAdapter(yifyResponses, throwing: throwing, hanging: hanging);
      final ds = SubtitleDatasource(
        tmdb: ApiClient(dio: tmdbDio),
        dio: yifyDio,
        yifyTimeout: yifyTimeout ?? const Duration(seconds: 15),
        subcatTimeout: subcatTimeout ?? const Duration(seconds: 25),
      );
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

    test(
        'SubtitleCat still wins when the YIFY chain THROWS '
        '(2026-08 Supergirl on-device fix)', () async {
      final (ds, _, _) = buildKeyless(
        {
          '/index.php': ResponseBody.fromBytes(utf8.encode(_scSearchPage), 200),
          '/subs/1532/Spider-Man-No-Way-Home-2021-1080p-YTS.html':
              ResponseBody.fromBytes(utf8.encode(_scDetailPage), 200),
          '/subs/1582/Spider-Man-No-Way-Home-2021-id.srt':
              ResponseBody.fromBytes(utf8.encode(_scSrtContent), 200),
        },
        // The YIFY movie page fails like Cloudflare on mobile — the OLD
        // sequential code's outer catch then returned null and SubtitleCat
        // never ran, the exact "no subtitles although one exists" report.
        throwing: {'/movie-imdb/tt10872600'},
      );
      final sub = await ds.fetchSubtitleFromMeta(
        title: 'Supergirl',
        year: '1984',
        imdbId: 'tt10872600',
      );
      expect(sub, isNotNull);
      expect(sub!.language, 'id');
      expect(sub.data, _scSrtContent); // SubtitleCat's content, not YIFY's.
    });

    test('SubtitleCat wins when YIFY HANGS past its per-source budget',
        () async {
      final (ds, _, _) = buildKeyless(
        {
          '/index.php': ResponseBody.fromBytes(utf8.encode(_scSearchPage), 200),
          '/subs/1532/Spider-Man-No-Way-Home-2021-1080p-YTS.html':
              ResponseBody.fromBytes(utf8.encode(_scDetailPage), 200),
          '/subs/1582/Spider-Man-No-Way-Home-2021-id.srt':
              ResponseBody.fromBytes(utf8.encode(_scSrtContent), 200),
        },
        // The YIFY page never answers (Cloudflare challenge hang on mobile).
        hanging: {'/movie-imdb/tt10872600'},
        yifyTimeout: const Duration(milliseconds: 50),
      );
      final sw = Stopwatch()..start();
      final sub = await ds.fetchSubtitleFromMeta(
        title: 'Supergirl',
        year: '1984',
        imdbId: 'tt10872600',
      );
      sw.stop();
      expect(sub, isNotNull);
      expect(sub!.language, 'id');
      expect(sub.data, _scSrtContent);
      // The hung YIFY was bounded by its per-source timeout — the whole
      // fetch returns promptly instead of blocking forever.
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('YIFY still wins when SubtitleCat errors (symmetric isolation)',
        () async {
      final (ds, _, _) = buildKeyless(
        {
          '/movie-imdb/tt10872600':
              ResponseBody.fromBytes(utf8.encode(_moviePage), 200),
          '/subtitles/spider-man-no-way-home-2021-indonesian-yify-395314':
              ResponseBody.fromBytes(utf8.encode(_detailPage), 200),
          '/subtitle/spider-man-no-way-home-2021-indonesian-yify-395314.zip':
              ResponseBody.fromBytes(_buildZip(), 200),
        },
        throwing: {'/index.php'},
      );
      final sub = await ds.fetchSubtitleFromMeta(imdbId: 'tt10872600');
      expect(sub, isNotNull);
      expect(sub!.language, 'id');
      expect(sub.data, _srtContent); // YIFY's content.
    });
  });
}
