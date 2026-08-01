import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/local/settings_service.dart';
import '../../domain/entities/video_source.dart';

/// ---------------------------------------------------------------------------
/// FilmKU Stream Source Pipeline
///
/// 1. [SourceAggregator] builds embed URLs from the TMDB id for every enabled
///    provider (vidsrc.to, 2embed, vidsrc.su, vidlink).
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

  /// Matches a URL token containing `.m3u8`/`.mp4`, capturing everything up
  /// to a quote/space/angle-bracket delimiter — NOT stopping at the
  /// extension.
  ///
  /// Stopping at the extension (as a substring match would) lets a mid-path
  /// match like `a.m3u8` inside `https://cdn.com/a.m3u8/b.ts` slip through as
  /// a broken "playable" URL. The full token is captured instead, and [scan]
  /// keeps only URLs whose path really ends in `.m3u8`/`.mp4` via
  /// [StreamSourceDataSource.shouldCaptureUrl] — the same filter the headless
  /// WebView path uses.
  static final RegExp _videoUrlRegex = RegExp(
    r'''https?:\\?/\\?/[^"'\s<>]+?\.(?:m3u8|mp4)[^"'\s<>]*''',
    caseSensitive: false,
  );

  static final RegExp _iframeRegex = RegExp(
    r'''<iframe[^>]+src=["']([^"']+)["']''',
    caseSensitive: false,
  );

  /// 2embed and friends render the player iframe with `data-src` (not `src`).
  static final RegExp _iframeDataSrcRegex = RegExp(
    r'''<iframe[^>]+data-src=["']([^"']+)["']''',
    caseSensitive: false,
  );

  /// Extracts unique stream-looking URLs from an HTML page.
  ///
  /// Every candidate passes through [StreamSourceDataSource.shouldCaptureUrl]
  /// so only URLs whose path actually ends in `.m3u8`/`.mp4` survive — the
  /// same guard the headless path applies. This rejects mid-path matches
  /// (`a.m3u8/b.ts` segment URLs) and bundles (`hls.m3u8.min.js`) that a
  /// substring match would wrongly capture.
  static List<String> scan(String html) {
    final cleaned = html.replaceAll(r'\/', '/');
    final urls = <String>{};
    for (final match in _videoUrlRegex.allMatches(cleaned)) {
      var url = match.group(0)!.replaceAll(r'\/', '/');
      // Raw HTML often entity-encodes URLs (`&amp;` for `&`); a literal
      // `&amp;` in a signed query breaks the CDN signature (HTTP 502 class).
      url = StreamSourceDataSource.decodeHtmlEntities(url);
      if (!StreamSourceDataSource.shouldCaptureUrl(url)) continue;
      if (url.endsWith('/')) url = url.substring(0, url.length - 1);
      urls.add(url);
    }
    return urls.toList();
  }

  /// Extracts nested iframe srcs (relative URLs are resolved against [base]).
  static List<String> scanIframes(String html, String base) {
    final baseUri = Uri.parse(base);
    final result = <String>[];
    for (final regex in [_iframeRegex, _iframeDataSrcRegex]) {
      for (final match in regex.allMatches(html)) {
        final src = match.group(1)!.replaceAll(r'\/', '/');
        // Same entity-decode as [scan]: iframe srcs can be entity-encoded
        // too, and the nested fetch would otherwise request a broken URL.
        final decoded = StreamSourceDataSource.decodeHtmlEntities(src);
        try {
          result.add(baseUri.resolve(decoded).toString());
        } catch (_) {
          // ignore unresolvable URLs
        }
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
    for (var m = 0; m < ifr.length; m++) {
      push(ifr[m].src);
      var ds = ifr[m].getAttribute("data-src");
      if (ds) push(ds);
    }
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

    // TEMP-DIAG: headless extraction silently returns nothing on-device
    // (zero streams found). Log start/done/capture/error so logcat shows
    // whether the WebView ever ran and what it captured. Remove together
    // with the other FILMKU_EXTRACT_* diagnostics.
    debugPrint('FILMKU_EXTRACT_HEADLESS start url=$url');

    void finish() {
      if (!completer.isCompleted) {
        final playable =
            urls.where(StreamSourceDataSource.shouldCaptureUrl).length;
        debugPrint(
          'FILMKU_EXTRACT_HEADLESS done captured=${urls.length} '
          'playable=$playable',
        );
        completer.complete(urls.toList());
      }
    }

    final timer = Timer(timeout, finish);
    // Redirects (e.g. vidsrc.to → vsembed.ru) fire `onLoadStop` multiple
    // times — only run one probe chain per extract() call.
    var probeStarted = false;

    HeadlessInAppWebView? view;
    try {
      // Records a candidate URL and stops the extraction as soon as a
      // playable one is seen. Shared by every interception callback below.
      void capture(String u) {
        // Same entity-decode as the Dio path: signed URLs observed here can
        // still carry `&amp;` when the player builds them from HTML/JS source.
        u = StreamSourceDataSource.decodeHtmlEntities(u);
        if (!StreamSourceDataSource.shouldCaptureUrl(u)) return;
        debugPrint('FILMKU_EXTRACT_HEADLESS capture url=$u');
        urls.add(u);
        finish();
      }

      view = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        // TEMP-DIAG + likely fix: the visible WebView fallback player passes
        // the app's mobile Chrome UA + explicit JS settings, but the headless
        // extractor previously sent the DEFAULT Android WebView UA — which
        // source CDNs may serve differently / block. Align the headless
        // WebView with the fallback player. Promote to a permanent fix if
        // this unblocks on-device extraction.
        initialSettings: InAppWebViewSettings(
          userAgent: AppConstants.defaultUserAgent,
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          javaScriptCanOpenWindowsAutomatically: true,
        ),
        onWebViewCreated: (controller) {
          debugPrint('FILMKU_EXTRACT_HEADLESS webViewCreated');
        },
        onLoadStart: (controller, _) {
          debugPrint('FILMKU_EXTRACT_HEADLESS onLoadStart url=$url');
        },
        onProgressChanged: (controller, progress) {
          if (progress % 25 == 0 || progress == 100) {
            debugPrint('FILMKU_EXTRACT_HEADLESS progress=$progress');
          }
        },
        onTitleChanged: (controller, title) {
          // e.g. "Just a moment…" reveals a Cloudflare challenge.
          debugPrint('FILMKU_EXTRACT_HEADLESS title=$title');
        },
        onConsoleMessage: (controller, consoleMessage) {
          debugPrint(
            'FILMKU_EXTRACT_HEADLESS console '
            'level=${consoleMessage.messageLevel} '
            'msg=${consoleMessage.message}',
          );
        },
        // Captures direct media URLs requested by any frame (nested iframes
        // included), which the top-level DOM scan cannot reach.
        onLoadResource: (controller, resource) {
          capture(resource.url?.toString() ?? '');
        },
        // Native-level interception: fires for EVERY network request from
        // ANY frame (nested cross-origin iframes included). Unlike
        // onLoadResource, this also catches fetch()/XHR requests — the way
        // modern JS players (hls.js, etc.) load their .m3u8 playlists.
        // This is the PRIMARY mechanism for nested-iframe player chains
        // like vidsrc.to → vsembed.ru → cloudorchestranova.com.
        shouldInterceptRequest: (controller, request) async {
          // `request.url` is a non-nullable WebUri in this API version.
          capture(request.url.toString());
          return null; // let the request proceed normally
        },
        // JS-level hooks as a safety net. NOTE: these are injected into the
        // main frame only — they cannot observe fetch/XHR inside nested
        // cross-origin iframes (same-origin policy). Keep
        // shouldInterceptRequest above; do not replace it with these.
        shouldInterceptAjaxRequest: (controller, ajaxRequest) async {
          capture(ajaxRequest.url?.toString() ?? '');
          return null; // proceed with the original request
        },
        shouldInterceptFetchRequest: (controller, fetchRequest) async {
          capture(fetchRequest.url?.toString() ?? '');
          return null; // proceed with the original request
        },
        onLoadStop: (controller, _) async {
          debugPrint(
            'FILMKU_EXTRACT_HEADLESS onLoadStop '
            'finalUrl=${controller.getUrl()}',
          );
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
        // TEMP-DIAG: sub-frame errors (blocked ads/trackers) are common and
        // NOT fatal — log but keep waiting instead of giving up. A main-frame
        // error (Cloudflare block, DNS fail) will stand out in logcat.
        onReceivedError: (controller, request, error) {
          // WebResourceError exposes `type` + `description` in this API
          // version (there is no numeric `errorCode` getter).
          debugPrint(
            'FILMKU_EXTRACT_HEADLESS onReceivedError '
            'type=${error.type} desc=${error.description} '
            'mainFrame=${request.isForMainFrame} url=${request.url}',
          );
        },
        onReceivedHttpError: (controller, request, response) {
          // Restrict to the main document so ad/tracker sub-requests (which
          // often 403/404) don't drown the log. `isForMainFrame` is nullable
          // in this API version, so compare explicitly.
          if (request.isForMainFrame == true) {
            debugPrint(
              'FILMKU_EXTRACT_HEADLESS onReceivedHttpError '
              'status=${response.statusCode} url=${request.url}',
            );
          }
        },
      );
      debugPrint('FILMKU_EXTRACT_HEADLESS running url=$url');
      await view.run();
      return await completer.future;
    } catch (error, stackTrace) {
      // TEMP-DIAG: headless WebView failure (e.g. WebView cannot be created
      // on device) is a prime suspect for the zero-stream bug — log it.
      debugPrint(
        'FILMKU_EXTRACT_HEADLESS error type=${error.runtimeType} '
        'error=$error',
      );
      debugPrint('FILMKU_EXTRACT_HEADLESS stack=$stackTrace');
      rethrow;
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
            if (item is String && item.isNotEmpty) {
              urls.add(StreamSourceDataSource.decodeHtmlEntities(item));
            }
          }
        }
      }
    } catch (_) {
      // JS evaluation failed; keep whatever we have.
    }
  }

  /// TEMP-DIAG: one-shot on-device headless WebView sanity check.
  ///
  /// Runs once per process before the first real headless extraction to
  /// separate two failure modes in logcat: "headless WebView broken on this
  /// device" vs "source sites specifically fail to expose media URLs". Loads
  /// a trivial page containing a well-known W3C test video and reports whether
  /// the WebView was created, the page loaded, the injected DOM probe ran, and
  /// network interception captured the media URL. Remove together with the
  /// other FILMKU_EXTRACT_* diagnostics.
  static bool _sanityRan = false;

  static Future<void> runSanityCheckOnce() async {
    if (_sanityRan) return;
    _sanityRan = true;
    debugPrint('FILMKU_EXTRACT_SANITY start');
    final urls = <String>{};
    var webViewCreated = false;
    var loadStopped = false;
    final completer = Completer<String>();
    final timer = Timer(const Duration(seconds: 25), () {
      if (!completer.isCompleted) completer.complete('timeout');
    });

    HeadlessInAppWebView? view;
    try {
      // Trivial page with a stable, well-known video URL (W3C test asset): if
      // the headless WebView works at all on-device, the injected DOM probe
      // finds the <video> and shouldInterceptRequest sees the .mp4 request.
      // `autoplay muted` + `mediaPlaybackRequiresUserGesture: false` force
      // the WebView to actually request the .mp4, so `shouldInterceptRequest`
      // (the mechanism the real extraction depends on) is genuinely tested.
      const testUrl = 'data:text/html,'
          '<html><body><video '
          'src="https://media.w3.org/2010/05/sintel/trailer.mp4" '
          'autoplay muted></video></body></html>';
      view = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(testUrl)),
        initialSettings: InAppWebViewSettings(
          userAgent: AppConstants.defaultUserAgent,
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
        ),
        onWebViewCreated: (controller) {
          webViewCreated = true;
          debugPrint('FILMKU_EXTRACT_SANITY webViewCreated');
        },
        onLoadStop: (controller, _) async {
          loadStopped = true;
          debugPrint('FILMKU_EXTRACT_SANITY onLoadStop');
          // Same injected DOM probe as the real extractor.
          await _runDomProbe(controller, urls);
          if (!completer.isCompleted) completer.complete('loadStop');
        },
        shouldInterceptRequest: (controller, request) async {
          final u = request.url.toString();
          if (u.endsWith('.mp4') || u.endsWith('.m3u8')) {
            debugPrint('FILMKU_EXTRACT_SANITY intercept=$u');
            urls.add(u);
          }
          return null;
        },
        onReceivedError: (controller, request, error) {
          debugPrint(
            'FILMKU_EXTRACT_SANITY error type=${error.type} '
            'desc=${error.description} url=${request.url}',
          );
        },
        onConsoleMessage: (controller, message) {
          debugPrint(
            'FILMKU_EXTRACT_SANITY console level=${message.messageLevel} '
            'msg=${message.message}',
          );
        },
      );
      await view.run();
      await completer.future;
      final captured =
          urls.where(StreamSourceDataSource.shouldCaptureUrl).toList();
      debugPrint(
        'FILMKU_EXTRACT_SANITY done webViewCreated=$webViewCreated '
        'loadStopped=$loadStopped captured=${captured.length}',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'FILMKU_EXTRACT_SANITY exception type=${error.runtimeType} '
        'error=$error',
      );
      debugPrint('FILMKU_EXTRACT_SANITY stack=$stackTrace');
    } finally {
      timer.cancel();
      await view?.dispose();
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

  /// Tries the fast Dio scan first, then the headless WebView fallback.
  static Future<VideoSource?> tryExtract(
    String sourceId,
    String label,
    String embedUrl, {
    required bool useHeadless,
  }) async {
    final direct = await _findDirectUrl(embedUrl);
    // TEMP-DIAG: log the fast Dio HTML-scan outcome per provider — did the
    // page even fetch, and did a direct .m3u8/.mp4 URL survive the scan?
    debugPrint(
      'FILMKU_EXTRACT_TRY sourceId=$sourceId label=$label '
      'dioDirect=${direct != null} headlessEnabled=$useHeadless',
    );
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
        // Same false-positive guard as the network interception path: only
        // keep URLs whose path actually ends in .m3u8/.mp4 (substring
        // matching would let script/API URLs through and then fail to play).
        final hit =
            candidates.where(StreamSourceDataSource.shouldCaptureUrl).toList();
        // TEMP-DIAG: how many candidates the headless WebView captured and
        // how many passed the guard — zero candidates means the WebView
        // never saw media requests, the core on-device question.
        debugPrint(
          'FILMKU_EXTRACT_TRY sourceId=$sourceId label=$label '
          'headlessCandidates=${candidates.length} headlessHit=${hit.length}',
        );
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
      } catch (error, stackTrace) {
        // Headless extraction failed; report no source for this provider.
        debugPrint(
          'FILMKU_EXTRACT_TRY sourceId=$sourceId label=$label '
          'headlessError type=${error.runtimeType} error=$error',
        );
        debugPrint('FILMKU_EXTRACT_TRY headlessStack=$stackTrace');
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

/// 2Embed.skin — a second live domain of the 2Embed ecosystem.
///
/// The legacy `2embed.cc` embed page serves `about:blank` in some regions,
/// while the `.skin` domain (same player backend, `streamsrcs.2embed.cc/`)
/// responds to TMDB ids with the correct movie page (verified 2026-08-01:
/// HTTP 200 + correct title for both trending and classic titles). Keeping
/// both domains registered gives the aggregator two independent chances at
/// the same backend, so one region-blocked/rotated domain does not kill the
/// source entirely.
///
/// NOTE: the actual player (`/swish`) is JS-rendered and did not emit any
/// .m3u8/.mp4 within 30s of autoplay-allowed headless probing — treat this
/// source as best-effort for NATIVE extraction and rely on its (verified
/// alive) embed page for the visible WebView fallback.
class TwoEmbedSkinExtractor extends StreamExtractor {
  const TwoEmbedSkinExtractor();

  @override
  String get sourceId => 'two_embed_skin';
  @override
  String get label => '2Embed.skin';

  @override
  String? buildEmbedUrl(int tmdbId) =>
      'https://www.2embed.skin/embed/movie/$tmdbId';

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

/// VidLink (https://vidlink.pro) — a modern JS/WASM-decrypted player.
///
/// The direct `.mp4?sign=...` URL only exists in the DOM after the player's
/// JS has run (verified 2026-08): a plain Dio HTML scan finds nothing, so this
/// source relies on [HeadlessStreamExtractor]'s DOM probe + network
/// interception, which captures the signed media URL as soon as it renders.
class VidLinkExtractor extends StreamExtractor {
  const VidLinkExtractor();

  @override
  String get sourceId => 'vidlink';
  @override
  String get label => 'VidLink';

  @override
  String? buildEmbedUrl(int tmdbId) => 'https://vidlink.pro/movie/$tmdbId';

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
  ///
  /// ORDER = reliability on the user's device (2026-08 on-device evidence):
  /// VidLink and 2Embed.skin are the only two whose VISIBLE WebView actually
  /// plays + auto-handoffs to mpv; vidsrc.to's CDN is ISP-blocked
  /// (`ERR_CONNECTION_REFUSED` in ~7s on the user's network) and 2embed.cc
  /// serves `about:blank` in some regions. Because auto-capture caps at the
  /// first 2 providers ([PlayerScreen.maxAutoCaptureProviders]), registry
  /// order directly decides which sources get a hidden-capture shot AND which
  /// one the visible WebView opens after exhaustion — so the proven-alive
  /// ones MUST come first.
  static const List<StreamExtractor> extractors = [
    VidLinkExtractor(),
    TwoEmbedSkinExtractor(),
    VidsrcToExtractor(),
    TwoEmbedExtractor(),
    VidsrcSuExtractor(),
  ];

  Future<List<VideoSource>> getSources(int tmdbId) async {
    final settings = SettingsService.instance;
    final useHeadless = settings.headlessExtraction;

    final enabled = [
      for (final extractor in extractors)
        if (settings.isSourceEnabled(extractor.sourceId)) extractor,
    ];
    // TEMP-DIAG: log which providers are enabled and the headless toggle —
    // if `enabled` is empty or headless is off, the zero-stream outcome is
    // explained before any extraction runs. Remove after investigation.
    debugPrint(
      'FILMKU_EXTRACT_AGGREGATOR movieId=$tmdbId '
      'enabled=${enabled.map((e) => e.sourceId).join(',')} '
      'headlessEnabled=$useHeadless',
    );

    if (useHeadless) {
      // TEMP-DIAG: verify the headless WebView pipeline works on this device
      // (created, loaded, DOM probe ran, interception fired) before trusting
      // the real extraction results. Remove after the investigation. The
      // 30s timeout guards getSources against any headless WebView hang.
      await HeadlessStreamExtractor.runSanityCheckOnce()
          .timeout(const Duration(seconds: 30), onTimeout: () {});
    }

    final results = await Future.wait([
      for (final extractor in enabled)
        _tryWithTimeout(extractor, tmdbId, useHeadless: useHeadless),
    ]);

    // TEMP-DIAG: per-provider outcome (source found or not) — pinpoints
    // whether every provider failed or only some. Remove after investigation.
    for (var i = 0; i < enabled.length; i++) {
      final hit = results[i];
      debugPrint(
        'FILMKU_EXTRACT_AGGREGATOR result '
        'sourceId=${enabled[i].sourceId} label=${enabled[i].label} '
        'hit=${hit != null}',
      );
    }

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

  /// Decodes HTML entities inside a scraped URL (single pass).
  ///
  /// Embed pages often entity-encode URLs in raw HTML/JS, e.g.
  /// `...video.mp4?sign=x&amp;t=y` — if that literal `&amp;` is played as-is,
  /// the CDN rejects the broken signature (the HTTP 502 class seen with
  /// VidLink). This turns the common entities back into their real
  /// characters. A single-pass regex (not chained `replaceAll`) is used so a
  /// literal `&amp;lt;` decodes to `&lt;`, never to `<`.
  static final RegExp _htmlEntityRegex = RegExp(
    r'&(#x?[0-9a-fA-F]+|amp|lt|gt|quot|apos|nbsp);',
  );

  static String decodeHtmlEntities(String url) {
    if (url.isEmpty || !url.contains('&')) return url;
    return url.replaceAllMapped(_htmlEntityRegex, (m) {
      final entity = m.group(1)!;
      switch (entity) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
        case 'nbsp':
          return ' ';
        default:
          // Numeric: `#38` (decimal) or `#x26` (hex).
          final isHex =
              entity.length > 2 && (entity[1] == 'x' || entity[1] == 'X');
          final digits = entity.substring(isHex ? 2 : 1);
          final code = int.tryParse(digits, radix: isHex ? 16 : 10);
          if (code == null || code > 0x10FFFF) return m.group(0)!;
          return String.fromCharCode(code);
      }
    });
  }

  /// Decides whether a scraped URL is a genuine playable media candidate.
  ///
  /// `shouldInterceptRequest` observes *every* network request — scripts,
  /// stylesheets, images and favicons included — so a resource named e.g.
  /// `hls.m3u8.min.js` would substring-match a naive `contains('.m3u8')`
  /// check and falsely stop the extraction. This filter keeps only real
  /// `.m3u8`/`.mp4` URLs, including ones with query strings (e.g. VidLink's
  /// `.../video.mp4?sign=...&t=...`).
  ///
  /// The check is performed on the URL **path** (before any `?`/`#`, with a
  /// trailing `/` trimmed), so a `.m3u8` appearing only inside a query value
  /// (`/error?file=master.m3u8`) is rejected while a signed
  /// `master.m3u8?token=...` (or a redirect-style `master.m3u8/`) is accepted.
  /// Requiring the suffix to be exactly `.m3u8`/`.mp4` also inherently
  /// rejects script/CSS/image names (`hls.m3u8.min.js`, `player.m3u8.css`)
  /// — a path cannot end in both extensions at once.
  static bool shouldCaptureUrl(String url) {
    if (url.isEmpty) return false;
    final path = url
        .split(RegExp(r'[?#]'))
        .first
        .toLowerCase()
        .replaceFirst(RegExp(r'/+$'), '');
    return path.endsWith('.m3u8') || path.endsWith('.mp4');
  }
}
