import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/local/settings_service.dart';
import '../../domain/entities/video_source.dart';

/// ---------------------------------------------------------------------------
/// FilmKU Stream Source Pipeline
///
/// 1. [SourceAggregator] builds embed URLs from the TMDB id for every enabled
///    provider (vidsrc.to, 2embed, vidsrc.su, cineby).
/// 2. [_HttpPageScanner] fetches each embed page with Dio and regex-scans it
///    (following one level of iframes) for direct `.m3u8` / `.mp4` links.
/// 3. [HeadlessStreamExtractor] — if nothing is found, an invisible headless
///    WebView loads the page and runs injected JS to locate the video element
///    or HLS config, returning direct stream URLs.
/// 4. The direct link is played in the NATIVE video player, so no ads from
///    the source sites ever render on screen.
///
/// ⚠️ Third-party sources are unofficial and unstable — they may change or
/// disappear at any time. Only stream content you are legally entitled to.
/// ---------------------------------------------------------------------------

/// Scans raw HTML for direct video URLs, optionally following iframes.
class _HttpPageScanner {
  _HttpPageScanner._();

  static final RegExp _videoUrlRegex = RegExp(
    r'''https?:\\?/\\?/[^"'\s<>]+?\.(?:m3u8|mp4)(?:\?[^"'\s<>]*)?''',
    caseSensitive: false,
  );

  static final RegExp _iframeRegex = RegExp(
    r'''<iframe[^>]+src=["']([^"']+)["']''',
    caseSensitive: false,
  );

  /// Extracts unique stream-looking URLs from an HTML page.
  static List<String> scan(String html) {
    final cleaned = html.replaceAll(r'\/', '/');
    final urls = <String>{};
    for (final match in _videoUrlRegex.allMatches(cleaned)) {
      var url = match.group(0)!.replaceAll(r'\/', '/');
      if (url.endsWith('/')) url = url.substring(0, url.length - 1);
      urls.add(url);
    }
    return urls.toList();
  }

  /// Extracts nested iframe srcs (relative URLs are resolved against [base]).
  static List<String> scanIframes(String html, String base) {
    final baseUri = Uri.parse(base);
    final result = <String>[];
    for (final match in _iframeRegex.allMatches(html)) {
      final src = match.group(1)!.replaceAll(r'\/', '/');
      try {
        result.add(baseUri.resolve(src).toString());
      } catch (_) {
        // ignore unresolvable URLs
      }
    }
    return result;
  }
}

/// Fetches pages with a mobile user-agent, like a real browser.
class _HtmlFetcher {
  _HtmlFetcher._();

  static final Dio _dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent': AppConstants.defaultUserAgent,
        'Referer': 'https://www.google.com/',
        'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
      },
      responseType: ResponseType.plain,
      followRedirects: true,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  static Future<String> get(String url) async {
    final response = await _dio.get<String>(url);
    return response.data ?? '';
  }
}

/// Loads a page in an invisible headless WebView and runs JS to find direct
/// video URLs (handles sites that render the player purely with JavaScript).
class HeadlessStreamExtractor {
  HeadlessStreamExtractor._();

  /// Injected script: collects video/source/iframe URLs and scans script
  /// config objects for common stream keys (`source`, `file`, `hls`, ...).
  static const String _extractionJs = r'''
(function () {
  var results = [];
  function push(u) {
    if (!u) return;
    u = String(u).replace(/\\\//g, "/").trim();
    if (u.indexOf("http") !== 0 && u.indexOf("//") === 0) u = "https:" + u;
    if (u && results.indexOf(u) === -1) results.push(u);
  }
  try {
    var vids = document.querySelectorAll("video");
    for (var i = 0; i < vids.length; i++) {
      push(vids[i].src || vids[i].currentSrc);
      var s = vids[i].querySelectorAll("source");
      for (var j = 0; j < s.length; j++) push(s[j].src);
    }
    var srcs = document.querySelectorAll("video source, source");
    for (var k = 0; k < srcs.length; k++) push(srcs[k].src);
    var ifr = document.querySelectorAll("iframe");
    for (var m = 0; m < ifr.length; m++) push(ifr[m].src);
    var scripts = document.querySelectorAll("script");
    for (var n = 0; n < scripts.length; n++) {
      var t = scripts[n].textContent || "";
      var re = /https?:\\?\/\\?\/[^"'\s]+?\.(?:m3u8|mp4)[^"'\s]*/gi;
      var mm;
      while ((mm = re.exec(t)) !== null) push(mm[0]);
      var keys = ["source", "file", "playlist", "url", "video_url",
                  "videoUrl", "hls", "link", "src", "stream"];
      for (var a = 0; a < keys.length; a++) {
        var kr = new RegExp('["\']' + keys[a] + '["\']\\s*[:=]\\s*["\']([^"\']+?)["\']', "gi");
        var km;
        while ((km = kr.exec(t)) !== null) {
          if (/m3u8|mp4/i.test(km[1])) push(km[1]);
        }
      }
    }
  } catch (e) {}
  return JSON.stringify(results);
})();
''';

  /// Extracts candidate stream URLs from [url] using a headless WebView.
  ///
  /// Modern embed players render inside nested (often cross-origin) iframes
  /// and may sit behind Cloudflare challenges, so a single DOM scan is not
  /// enough. Two mechanisms are combined:
  ///  1. [InAppWebView.onLoadResource] observes every network request the
  ///     page makes — including requests from nested iframes — and captures
  ///     direct `.m3u8`/`.mp4` URLs as soon as the player fetches them.
  ///  2. The injected DOM script runs again a few times after `onLoadStop`,
  ///     giving Cloudflare checks and JS players time to settle.
  static Future<List<String>> extract(
    String url, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = Completer<List<String>>();
    final urls = <String>{};

    void finish() {
      if (!completer.isCompleted) completer.complete(urls.toList());
    }

    final timer = Timer(timeout, finish);
    // Redirects (e.g. vidsrc.to → vsembed.ru) fire `onLoadStop` multiple
    // times — only run one probe chain per extract() call.
    var probeStarted = false;

    HeadlessInAppWebView? view;
    try {
      view = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        // Captures direct media URLs requested by any frame (nested iframes
        // included), which the top-level DOM scan cannot reach.
        onLoadResource: (controller, resource) {
          final u = resource.url?.toString() ?? '';
          if (u.isNotEmpty && _ScrapeHelper.looksLikeVideo(u)) {
            urls.add(u);
            finish();
          }
        },
        onLoadStop: (controller, _) async {
          if (probeStarted || completer.isCompleted) return;
          probeStarted = true;
          await _runDomProbe(controller, urls);
          // Cloudflare auto-resolves and SPA players mount their <video> a
          // moment after load — probe a few more times.
          for (var i = 0; i < 4 && !completer.isCompleted; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 2000));
            if (completer.isCompleted) return;
            await _runDomProbe(controller, urls);
          }
          finish();
        },
        // Sub-frame errors (blocked ads/trackers) are common and not fatal —
        // keep waiting instead of giving up on the first error.
        onReceivedError: (controller, request, error) {},
      );
      await view.run();
      return await completer.future;
    } finally {
      timer.cancel();
      await view?.dispose();
    }
  }

  /// Runs the injected DOM script and merges any video URLs it finds.
  static Future<void> _runDomProbe(
    InAppWebViewController controller,
    Set<String> urls,
  ) async {
    try {
      final result = await controller.evaluateJavascript(source: _extractionJs);
      if (result is String) {
        final decoded = jsonDecode(result);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is String && item.isNotEmpty) urls.add(item);
          }
        }
      }
    } catch (_) {
      // JS evaluation failed; keep whatever we have.
    }
  }
}

/// Shared extraction flow used by every provider extractor.
class _ScrapeHelper {
  _ScrapeHelper._();

  static final List<(RegExp, String)> _qualityPatterns = [
    (RegExp(r'1080[pP]'), '1080p'),
    (RegExp(r'720[pP]'), '720p'),
    (RegExp(r'480[pP]'), '480p'),
    (RegExp(r'360[pP]'), '360p'),
  ];

  static String detectQuality(String url) {
    for (final (pattern, label) in _qualityPatterns) {
      if (pattern.hasMatch(url)) return label;
    }
    return 'Auto';
  }

  static bool looksLikeVideo(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4?') ||
        lower.endsWith('.mp4');
  }

  /// Tries the fast Dio scan first, then the headless WebView fallback.
  static Future<VideoSource?> tryExtract(
    String sourceId,
    String label,
    String embedUrl, {
    required bool useHeadless,
  }) async {
    final direct = await _findDirectUrl(embedUrl);
    if (direct != null) {
      return VideoSource(
        sourceId: sourceId,
        label: label,
        videoUrl: direct,
        embedUrl: embedUrl,
        quality: detectQuality(direct),
      );
    }

    if (useHeadless) {
      try {
        final candidates = await HeadlessStreamExtractor.extract(embedUrl);
        final hit = candidates.where(looksLikeVideo).toList();
        if (hit.isNotEmpty) {
          final best = hit.first;
          return VideoSource(
            sourceId: sourceId,
            label: label,
            videoUrl: best,
            embedUrl: embedUrl,
            quality: detectQuality(best),
          );
        }
      } catch (_) {
        // Headless extraction failed; report no source for this provider.
      }
    }
    return null;
  }

  /// Direct HTML scan; follows one level of iframe nesting.
  static Future<String?> _findDirectUrl(String embedUrl) async {
    try {
      final page = await _HtmlFetcher.get(embedUrl);
      var urls = _HttpPageScanner.scan(page);

      if (urls.isNotEmpty) {
        return _preferHls(urls);
      }

      final iframes = _HttpPageScanner.scanIframes(page, embedUrl);
      for (final nested in iframes) {
        try {
          final nestedPage = await _HtmlFetcher.get(nested);
          final nestedUrls = _HttpPageScanner.scan(nestedPage);
          if (nestedUrls.isNotEmpty) return _preferHls(nestedUrls);
        } catch (_) {
          // try next iframe
        }
      }
    } catch (_) {
      // page unreachable — headless fallback may still work
    }
    return null;
  }

  /// Prefers `.m3u8` (HLS) streams over `.mp4` files.
  static String _preferHls(List<String> urls) {
    final sorted = [...urls];
    sorted.sort((a, b) {
      final aHls = a.toLowerCase().contains('.m3u8') ? 0 : 1;
      final bHls = b.toLowerCase().contains('.m3u8') ? 0 : 1;
      return aHls.compareTo(bHls);
    });
    return sorted.first;
  }
}

/// Base class for a single stream provider.
abstract class StreamExtractor {
  const StreamExtractor();

  String get sourceId;
  String get label;

  /// Embed page URL built from the TMDB id.
  String? buildEmbedUrl(int tmdbId);

  Future<VideoSource?> extract(int tmdbId, {required bool useHeadless});
}

class VidsrcToExtractor extends StreamExtractor {
  const VidsrcToExtractor();

  @override
  String get sourceId => 'vidsrc_to';
  @override
  String get label => 'VidSrc.to';

  @override
  String? buildEmbedUrl(int tmdbId) => 'https://vidsrc.to/embed/movie/$tmdbId';

  @override
  Future<VideoSource?> extract(int tmdbId, {required bool useHeadless}) {
    final embedUrl = buildEmbedUrl(tmdbId);
    if (embedUrl == null) return Future.value(null);
    return _ScrapeHelper.tryExtract(
      sourceId,
      label,
      embedUrl,
      useHeadless: useHeadless,
    );
  }
}

class TwoEmbedExtractor extends StreamExtractor {
  const TwoEmbedExtractor();

  @override
  String get sourceId => 'two_embed';
  @override
  String get label => '2Embed';

  @override
  String? buildEmbedUrl(int tmdbId) =>
      'https://www.2embed.cc/embed/movie/$tmdbId';

  @override
  Future<VideoSource?> extract(int tmdbId, {required bool useHeadless}) {
    final embedUrl = buildEmbedUrl(tmdbId);
    if (embedUrl == null) return Future.value(null);
    return _ScrapeHelper.tryExtract(
      sourceId,
      label,
      embedUrl,
      useHeadless: useHeadless,
    );
  }
}

class VidsrcSuExtractor extends StreamExtractor {
  const VidsrcSuExtractor();

  @override
  String get sourceId => 'vidsrc_su';
  @override
  String get label => 'VidSrc.su';

  @override
  String? buildEmbedUrl(int tmdbId) => 'https://vidsrc.su/embed/movie/$tmdbId';

  @override
  Future<VideoSource?> extract(int tmdbId, {required bool useHeadless}) {
    final embedUrl = buildEmbedUrl(tmdbId);
    if (embedUrl == null) return Future.value(null);
    return _ScrapeHelper.tryExtract(
      sourceId,
      label,
      embedUrl,
      useHeadless: useHeadless,
    );
  }
}

class CinebyExtractor extends StreamExtractor {
  const CinebyExtractor();

  @override
  String get sourceId => 'cineby';
  @override
  String get label => 'Cineby';

  @override
  String? buildEmbedUrl(int tmdbId) => 'https://embed.cineby.ru/movie/$tmdbId';

  @override
  Future<VideoSource?> extract(int tmdbId, {required bool useHeadless}) {
    final embedUrl = buildEmbedUrl(tmdbId);
    if (embedUrl == null) return Future.value(null);
    return _ScrapeHelper.tryExtract(
      sourceId,
      label,
      embedUrl,
      useHeadless: useHeadless,
    );
  }
}

/// Orchestrates every enabled provider and aggregates playable sources.
class SourceAggregator {
  SourceAggregator();

  /// Provider registry — shown in Settings for toggling.
  static const List<StreamExtractor> extractors = [
    VidsrcToExtractor(),
    TwoEmbedExtractor(),
    VidsrcSuExtractor(),
    CinebyExtractor(),
  ];

  Future<List<VideoSource>> getSources(int tmdbId) async {
    final settings = SettingsService.instance;
    final useHeadless = settings.headlessExtraction;

    final results = await Future.wait([
      for (final extractor in extractors)
        if (settings.isSourceEnabled(extractor.sourceId))
          _tryWithTimeout(extractor, tmdbId, useHeadless: useHeadless),
    ]);

    return results.whereType<VideoSource>().toList();
  }

  Future<VideoSource?> _tryWithTimeout(
    StreamExtractor extractor,
    int tmdbId, {
    required bool useHeadless,
  }) async {
    try {
      return await extractor
          .extract(tmdbId, useHeadless: useHeadless)
          .timeout(const Duration(seconds: 45));
    } catch (_) {
      return null;
    }
  }
}

/// Data source exposing aggregated stream sources to the repository.
class StreamSourceDataSource {
  StreamSourceDataSource({SourceAggregator? aggregator})
      : _aggregator = aggregator ?? SourceAggregator();

  final SourceAggregator _aggregator;

  Future<List<VideoSource>> getMovieSources(int tmdbId) =>
      _aggregator.getSources(tmdbId);
}
