import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';

/// A subtitle ready to be loaded into the native player (raw SRT/WebVTT
/// text, so [SubtitleTrack.data] can render it directly).
class SubtitleInfo {
  const SubtitleInfo({
    required this.title,
    required this.language,
    required this.data,
  });

  /// Human-readable label (e.g. 'Indonesian').
  final String title;

  /// ISO language code (e.g. 'id' / 'en').
  final String language;

  /// Full SRT (or WebVTT) subtitle content.
  final String data;
}

/// A subtitle entry parsed from a YIFY subtitle listing page.
class SubtitleLink {
  const SubtitleLink({
    required this.path,
    required this.language,
    required this.label,
  });

  /// Relative subtitle detail path, e.g. `/subtitles/{movie}-indonesian-yify-123`.
  final String path;

  /// ISO language code ('id', 'en', …) or 'xx' when unknown.
  final String language;

  /// Human-readable language label (e.g. 'Indonesian').
  final String label;
}

/// A subtitle entry parsed from a SubtitleCat detail page — a DIRECT `.srt`
/// link (no zip, no anti-bot), with the language encoded in the filename
/// suffix (`{name}-id.srt`).
class SubtitleCatLink {
  const SubtitleCatLink({
    required this.path,
    required this.language,
    required this.label,
  });

  /// Absolute `.srt` path, e.g. `/subs/1582/Movie-2021-1080p-id.srt`.
  final String path;

  /// ISO-ish language code ('id', 'en', 'es-419', …) or 'xx' when unknown.
  final String language;

  /// Human-readable language label (e.g. 'Indonesian').
  final String label;
}

/// ---------------------------------------------------------------------------
/// External subtitle fetching for the native player.
///
/// The stream sources (2Embed/2vcdn, VidLink, vidsrc) serve playlists with NO
/// subtitle tracks at all — verified 2026-08: the 2vcdn master playlist for a
/// random movie is 144 bytes with zero `#EXT-X-MEDIA` lines — so "built-in"
/// subtitles never appear no matter what the player does. [SubtitleDatasource]
/// fetches them EXTERNALLY instead, chaining two FREE keyless sources:
///
///  1. **YIFY subtitles** (`yifysubtitles.ch/movie-imdb/{tt}`) — needs the
///     TMDB→IMDB id. Indonesian preferred, English fallback. The `.zip`
///     download MUST carry the detail page as `Referer` (Cloudflare 403s it
///     otherwise — probed 2026-08).
///  2. **SubtitleCat** (`subtitlecat.com`) — search by TMDB title + year (no
///     IMDB id needed), then the release detail pages expose DIRECT `.srt`
///     links with the language in the filename (`-id.srt`, `-en.srt`). Also
///     Indonesian preferred, English fallback.
///
/// The caller loads the result via media_kit's `SubtitleTrack.data(...)`.
/// Best-effort: ANY failure returns null and must never block or fail
/// playback.
/// ---------------------------------------------------------------------------
class SubtitleDatasource {
  SubtitleDatasource({ApiClient? tmdb, Dio? dio})
      : _tmdb = tmdb ?? ApiClient(),
        _dio = dio ?? _createDio();

  final ApiClient _tmdb;
  final Dio _dio;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        headers: {
          'User-Agent': AppConstants.defaultUserAgent,
          'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
        },
        responseType: ResponseType.bytes,
        followRedirects: true,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
  }

  /// Fetches the best available subtitle for [tmdbId]: Indonesian first,
  /// English as fallback, across both providers (YIFY then SubtitleCat).
  /// Returns null when neither source has a usable subtitle for the movie,
  /// or ANY network/parse error occurs.
  Future<SubtitleInfo?> fetchSubtitle(int tmdbId) async {
    try {
      final imdbId = await _fetchImdbId(tmdbId);
      if (imdbId != null) {
        final yify = await _fetchFromYify(imdbId);
        if (yify != null) return yify;
      }
      // Explicit `await` is REQUIRED: `return _fetchFromSubtitleCatByTmdb(...)`
      // (implicit return-await) would let a CDN 404 escape the try/catch —
      // Dart only routes errors through an enclosing catch for EXPLICIT
      // awaits (verified empirically 2026-08).
      return await _fetchFromSubtitleCatByTmdb(tmdbId);
    } catch (_) {
      return null;
    }
  }

  /// Fetches the best available subtitle using movie metadata the CALLER
  /// already has — so subtitles work WITHOUT a TMDB API key.
  ///
  /// [title] (+ [year]) is enough for SubtitleCat (it searches by title);
  /// [imdbId] (when already known) enables the YIFY chain directly. Metadata
  /// the caller lacks is looked up via TMDB as a best-effort fallback
  /// (requires an API key, which may be absent on some builds — the 2026-08
  /// reason iOS builds showed "no subtitles" while the laptop probe worked).
  ///
  /// Indonesian first, English as fallback; any network/parse error returns
  /// null (subtitles must never break playback).
  Future<SubtitleInfo?> fetchSubtitleFromMeta({
    int? tmdbId,
    String? title,
    String? year,
    String? imdbId,
  }) async {
    try {
      var resolvedImdb = imdbId;
      if (resolvedImdb == null && tmdbId != null) {
        resolvedImdb = await _fetchImdbId(tmdbId);
      }
      if (resolvedImdb != null) {
        final yify = await _fetchFromYify(resolvedImdb);
        if (yify != null) return yify;
      }
      // YIFY had nothing (or no IMDB id) — SubtitleCat only needs the title
      // (+ year), so it works with no TMDB key when the caller passes the
      // metadata (the common case from the movie object in the UI).
      if (title != null && title.trim().isNotEmpty) {
        final subcat = await _fetchFromSubtitleCat(title, year: year);
        if (subcat != null) return subcat;
      }
      // Last resort: TMDB-only lookups (title via TMDB for SubtitleCat).
      // Explicit `await` (see fetchSubtitle): implicit return-await would
      // let a CDN 404 escape the try/catch.
      if (tmdbId != null) {
        return await _fetchFromSubtitleCatByTmdb(tmdbId);
      }
      return null;
    } catch (_) {
      // Best-effort — subtitles must never break playback.
      return null;
    }
  }

  /// YIFY flow: IMDB page → subtitle entries → detail page → `.zip` download
  /// (with the detail page as Referer) → extract `.srt`.
  Future<SubtitleInfo?> _fetchFromYify(String imdbId) async {
    final moviePage = await _getText(
      'https://yifysubtitles.ch/movie-imdb/$imdbId',
    );
    final links = parseSubtitleLinks(moviePage);
    if (links.isEmpty) return null;
    // Indonesian preferred, English fallback, then whatever exists.
    var pick = links.firstWhere(
      (l) => l.language == 'id',
      orElse: () => links.firstWhere(
        (l) => l.language == 'en',
        orElse: () => links.first,
      ),
    );
    final detail = await _getText('https://yifysubtitles.ch${pick.path}');
    final zipPath = parseZipLink(detail);
    if (zipPath == null) return null;
    final bytes = await _getBytes(
      'https://yifysubtitles.ch$zipPath',
      // YIFY serves the .zip through Cloudflare which 403s requests WITHOUT
      // a same-origin Referer (probed 2026-08: UA+Referer → HTTP 200 real
      // zip; UA alone → 403 "Just a moment…" challenge). The Referer must
      // be the subtitle DETAIL page — that's what a real browser sends
      // when clicking the download button. Without this the whole subtitle
      // flow silently returned null (the 403 body never parsed as a zip).
      headers: {'Referer': 'https://yifysubtitles.ch${pick.path}'},
    );
    final srt = extractSrtFromZip(bytes);
    if (srt == null || srt.trim().isEmpty) return null;
    return SubtitleInfo(
      title: pick.label,
      language: pick.language,
      data: srt,
    );
  }

  /// SubtitleCat flow using only the TMDB id: title + year are fetched via
  /// TMDB first (requires an API key), then the keyless search follows.
  Future<SubtitleInfo?> _fetchFromSubtitleCatByTmdb(int tmdbId) async {
    final titleInfo = await _fetchTitle(tmdbId);
    if (titleInfo == null) return null;
    return await _fetchFromSubtitleCat(titleInfo.title, year: titleInfo.year);
  }

  /// SubtitleCat flow: search by [title] (+ [year]) → search page → release
  /// detail pages → direct `.srt` download. Indonesian preferred, English
  /// fallback. No TMDB/IMDB needed — the caller may pass the title straight
  /// from the movie object it already holds.
  Future<SubtitleInfo?> _fetchFromSubtitleCat(String title,
      {String? year}) async {
    // Search WITH the year first (more precise match), then retry WITHOUT it
    // — SubtitleCat titles sometimes omit the release year, so a year-scoped
    // search can miss a subtitle the plain-title search finds (2026-08 user
    // report: some movies played with NO subtitle at all even though one
    // existed under a year-less listing).
    final queries = <String>[
      if (year != null && year.isNotEmpty) '$title $year',
      title,
    ];
    for (final query in queries) {
      final found = await _searchSubtitleCat(query);
      if (found != null) return found;
    }
    return null;
  }

  /// One SubtitleCat search: [query] → search page → release detail pages →
  /// direct `.srt` download. Indonesian preferred, English fallback.
  Future<SubtitleInfo?> _searchSubtitleCat(String query) async {
    final searchHtml = await _getText(
      'https://subtitlecat.com/index.php'
      '?search=${Uri.encodeQueryComponent(query)}',
    );
    final slugs = parseSubtitleCatSlugs(searchHtml);
    if (slugs.isEmpty) return null;
    // Try up to 8 release groups — the first page usually has a subtitle,
    // but some releases only carry a few languages (a 2026-08 probe of a
    // popular movie found 55 release pages; Indonesian appeared only on
    // SOME of them). 8 > 5 widens the net for old/obscure films without
    // ballooning the request count.
    for (final slug in slugs.take(8)) {
      try {
        final detail = await _getText('https://subtitlecat.com/$slug');
        final links = parseSubtitleCatSrtLinks(detail);
        if (links.isEmpty) continue;
        final pick = links.firstWhere(
          (l) => l.language == 'id',
          orElse: () => links.firstWhere(
            (l) => l.language == 'en',
            orElse: () => links.first,
          ),
        );
        final srt = await _getText('https://subtitlecat.com${pick.path}');
        if (srt.trim().isEmpty) continue;
        // Defensive: a 200 HTML page (error/redirect shell) is NOT a
        // subtitle — never hand the player garbage text.
        final head =
            srt.trimLeft().substring(0, math.min(srt.trimLeft().length, 64));
        final lowerHead = head.toLowerCase();
        if (lowerHead.startsWith('<!doctype') ||
            lowerHead.startsWith('<html')) {
          continue;
        }
        return SubtitleInfo(
          title: pick.label,
          language: pick.language,
          data: srt,
        );
      } catch (_) {
        // One release page failed (timeout/404) — try the next one.
        continue;
      }
    }
    return null;
  }

  Future<String?> _fetchImdbId(int tmdbId) async {
    final data = await _tmdb.get('/movie/$tmdbId/external_ids');
    // Real TMDB responses decode to a Map; be tolerant of a raw JSON string
    // (some HTTP clients / adapters skip the content-type-driven decode).
    final map = data is Map<String, dynamic>
        ? data
        : (data is String ? _tryDecodeMap(data) : null);
    if (map == null) return null;
    final imdb = map['imdb_id'];
    return (imdb is String && imdb.startsWith('tt')) ? imdb : null;
  }

  /// Fetches the TMDB title + release year — SubtitleCat searches by title
  /// (it has no IMDB-id lookup), so this is its identifier.
  Future<({String title, String year})?> _fetchTitle(int tmdbId) async {
    final data = await _tmdb.get('/movie/$tmdbId');
    final map = data is Map<String, dynamic>
        ? data
        : (data is String ? _tryDecodeMap(data) : null);
    if (map == null) return null;
    final title = map['title'];
    if (title is! String || title.trim().isEmpty) return null;
    final releaseDate = map['release_date'];
    final year = (releaseDate is String && releaseDate.length >= 4)
        ? releaseDate.substring(0, 4)
        : '';
    return (title: title, year: year);
  }

  static Map<String, dynamic>? _tryDecodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _getText(String url) async {
    final r = await _dio.get<List<int>>(url);
    return utf8.decode(r.data ?? const <int>[], allowMalformed: true);
  }

  Future<List<int>> _getBytes(String url,
      {Map<String, String>? headers}) async {
    final r = await _dio.get<List<int>>(
      url,
      options: Options(headers: headers),
    );
    return r.data ?? const <int>[];
  }

  // -------------------------------------------------------------------------
  // Pure parsing (exposed for tests)
  // -------------------------------------------------------------------------

  static final RegExp _subtitleLinkRegex = RegExp(
    r'''href="(/subtitles/[^"]+)"''',
    caseSensitive: false,
  );

  static final RegExp _zipLinkRegex = RegExp(
    r'''href="(/subtitle/[^"]+\.zip)"''',
    caseSensitive: false,
  );

  /// Real YIFY subtitle slugs always end with `-yify-{id}`
  /// (e.g. `spider-man-2021-indonesian-yify-395314`). The generic
  /// `/subtitles/...` href match ALSO catches navigation/utility links
  /// (`/subtitles/popular`, pagination…) — those must never be picked as a
  /// subtitle, especially by the fallback when a movie has no Indonesian or
  /// English entry (reviewer finding, 2026-08).
  static final RegExp _yifySlugRegex = RegExp(
    r'-yify-\d+$',
    caseSensitive: false,
  );

  /// SubtitleCat release-group detail pages: `href="subs/{id}/{name}.html"`.
  static final RegExp _scSlugRegex = RegExp(
    r'''href="(subs/\d+/[^"]+\.html)"''',
    caseSensitive: false,
  );

  /// SubtitleCat direct subtitle files: `href="/subs/{id}/{name}-{lang}.srt"`.
  static final RegExp _scSrtRegex = RegExp(
    r'''href="(/subs/\d+/[^"]+\.srt)"''',
    caseSensitive: false,
  );

  /// The language suffix at the END of a SubtitleCat `.srt` filename
  /// (`-id.srt`, `-en.srt`, `-pt-BR.srt`, `-es-419.srt`).
  static final RegExp _scLangSuffixRegex = RegExp(
    r'-([a-z]{2}(?:-[a-z0-9]{2,3})?)\.srt$',
    caseSensitive: false,
  );

  /// Language tokens as they appear in YIFY subtitle slugs
  /// (`{movie}-{year}-{language}-yify-{id}`).
  static const Map<String, String> _languageTokens = {
    'indonesian': 'id',
    'english': 'en',
    'arabic': 'ar',
    'spanish': 'es',
    'french': 'fr',
    'brazillian-portuguese': 'pb',
    'portuguese': 'pt',
    'vietnamese': 'vi',
    'chinese': 'zh',
    'german': 'de',
    'hindi': 'hi',
    'malay': 'ms',
    'japanese': 'ja',
    'korean': 'ko',
    'thai': 'th',
    'turkish': 'tr',
    'italian': 'it',
    'dutch': 'nl',
    'russian': 'ru',
    'polish': 'pl',
    'ukrainian': 'uk',
    'hebrew': 'he',
    'swedish': 'sv',
  };

  /// SubtitleCat suffixes are already ISO-ish — map the common ones to
  /// readable labels; anything else falls back to the raw suffix.
  static const Map<String, String> _scLanguageNames = {
    'id': 'Indonesian',
    'en': 'English',
    'ar': 'Arabic',
    'es': 'Spanish',
    'es-419': 'Spanish (Latin America)',
    'fr': 'French',
    'pt': 'Portuguese',
    'pt-br': 'Portuguese (Brazil)',
    'ru': 'Russian',
    'zh-cn': 'Chinese (Simplified)',
    'zh-tw': 'Chinese (Traditional)',
    'de': 'German',
    'hi': 'Hindi',
    'ja': 'Japanese',
    'ko': 'Korean',
    'th': 'Thai',
    'tr': 'Turkish',
    'it': 'Italian',
    'nl': 'Dutch',
    'vi': 'Vietnamese',
    'ms': 'Malay',
    'sr': 'Serbian',
    'ur': 'Urdu',
    'el': 'Greek',
    'mn': 'Mongolian',
    'pl': 'Polish',
    'uk': 'Ukrainian',
    'he': 'Hebrew',
    'sv': 'Swedish',
    'sh': 'Serbo-Croatian',
    'sl': 'Slovenian',
    'cs': 'Czech',
    'hu': 'Hungarian',
    'ro': 'Romanian',
    'bg': 'Bulgarian',
  };

  /// Extracts the subtitle entries from a YIFY movie page. Entries are
  /// de-duplicated by path, in page order.
  @visibleForTesting
  static List<SubtitleLink> parseSubtitleLinks(String html) {
    final links = <SubtitleLink>[];
    final seen = <String>{};
    for (final match in _subtitleLinkRegex.allMatches(html)) {
      final path = match.group(1)!;
      if (!seen.add(path)) continue;
      final slug = path.split('/').last.toLowerCase();
      if (!_yifySlugRegex.hasMatch(slug)) continue; // real subtitle links only
      var language = 'xx';
      var label = 'Subtitle';
      for (final entry in _languageTokens.entries) {
        if (slug.contains(entry.key)) {
          language = entry.value;
          label = _titleCase(entry.key);
          break;
        }
      }
      links.add(SubtitleLink(path: path, language: language, label: label));
    }
    return links;
  }

  /// Extracts the `.zip` download path from a YIFY subtitle detail page.
  @visibleForTesting
  static String? parseZipLink(String detailHtml) {
    final match = _zipLinkRegex.firstMatch(detailHtml);
    return match?.group(1);
  }

  /// Extracts the release-group slugs from a SubtitleCat search page,
  /// de-duplicated, in page order.
  @visibleForTesting
  static List<String> parseSubtitleCatSlugs(String html) {
    final slugs = <String>[];
    final seen = <String>{};
    for (final match in _scSlugRegex.allMatches(html)) {
      final slug = match.group(1)!;
      if (seen.add(slug)) slugs.add(slug);
    }
    return slugs;
  }

  /// Extracts the direct `.srt` links from a SubtitleCat detail page, with
  /// the language decoded from the filename suffix (`-id.srt` → 'id').
  /// De-duplicated by path, in page order.
  @visibleForTesting
  static List<SubtitleCatLink> parseSubtitleCatSrtLinks(String html) {
    final links = <SubtitleCatLink>[];
    final seen = <String>{};
    for (final match in _scSrtRegex.allMatches(html)) {
      final path = match.group(1)!;
      if (!seen.add(path)) continue;
      final suffix =
          _scLangSuffixRegex.firstMatch(path)?.group(1)?.toLowerCase();
      links.add(SubtitleCatLink(
        path: path,
        language: suffix ?? 'xx',
        label: suffix == null ? 'Subtitle' : _scLanguageNames[suffix] ?? suffix,
      ));
    }
    return links;
  }

  /// Extracts the SRT/WebVTT text from a YIFY subtitle `.zip` archive.
  /// Returns null on any failure (not a zip / no subtitle file inside).
  @visibleForTesting
  static String? extractSrtFromZip(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? pick;
      for (final file in archive) {
        if (!file.isFile) continue;
        final name = file.name.toLowerCase();
        if (name.endsWith('.srt') || name.endsWith('.vtt')) {
          pick = file;
          break;
        }
      }
      if (pick == null) {
        // Fallback: the zip may contain a subtitle with no usable extension —
        // pick the LARGEST file (subtitle text dominates a zip; a stray
        // readme/.nfo is small and would lose the tie only on empty zips).
        var bestSize = -1;
        for (final file in archive) {
          if (!file.isFile) continue;
          final size = file.content.length;
          if (size > bestSize) {
            bestSize = size;
            pick = file;
          }
        }
      }
      if (pick == null) return null;
      final content = pick.content;
      var text = utf8.decode(content, allowMalformed: true);
      // Strip a UTF-8 BOM if present.
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      return text;
    } catch (_) {
      return null;
    }
  }

  static String _titleCase(String input) {
    if (input.isEmpty) return input;
    return input
        .split('-')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
