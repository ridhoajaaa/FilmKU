import 'dart:convert';

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

/// ---------------------------------------------------------------------------
/// External subtitle fetching for the native player.
///
/// The stream sources (2Embed/2vcdn, VidLink, vidsrc) serve playlists with NO
/// subtitle tracks at all — verified 2026-08: the 2vcdn master playlist for a
/// random movie is 144 bytes with zero `#EXT-X-MEDIA` lines — so "built-in"
/// subtitles never appear no matter what the player does. [SubtitleDatasource]
/// fetches them EXTERNALLY instead:
///
///  1. TMDB id → IMDB id (`/movie/{id}/external_ids`).
///  2. YIFY subtitles (`yifysubtitles.ch/movie-imdb/{tt}`) — free, NO API key.
///  3. Prefer the INDONESIAN subtitle, fall back to English.
///  4. Download the `.zip`, extract the `.srt`, return it as text.
///
/// The caller loads it via media_kit's `SubtitleTrack.data(...)`. Best-effort:
/// ANY failure returns null and must never block or fail playback.
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
  /// English as fallback. Returns null when the movie has no subtitle on
  /// YIFY, the TMDB id is unknown, or ANY network/parse error occurs.
  Future<SubtitleInfo?> fetchSubtitle(int tmdbId) async {
    try {
      final imdbId = await _fetchImdbId(tmdbId);
      if (imdbId == null) return null;
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
    } catch (_) {
      // Best-effort — subtitles must never break playback.
      return null;
    }
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
