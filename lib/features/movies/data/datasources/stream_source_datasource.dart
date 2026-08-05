import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/local/settings_service.dart';
import '../../../../core/net/hls_relay.dart';
import '../../../../core/webview/capture_webview_settings.dart';
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
      if (!StreamSourceDataSource.isDirectPlayableUrl(url)) continue;
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
            urls.where(StreamSourceDataSource.isDirectPlayableUrl).length;
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
        // Only a genuinely replayable URL counts: an EMPTY `headers={}`
        // template (VidLink) is rejected by the CDN with 428 when replayed
        // outside the page, so capturing it would hand mpv a doomed URL.
        if (!StreamSourceDataSource.isDirectPlayableUrl(u)) return;
        debugPrint('FILMKU_EXTRACT_HEADLESS capture url=$u');
        urls.add(u);
        finish();
      }

      view = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        // Shared builder: mobile Chrome UA + explicit JS settings AND the
        // interception flags — iOS defaults shouldIntercept* to false, so
        // without this the headless extractor can never capture media URLs
        // on iOS (zero-stream bug). See capture_webview_settings.dart.
        initialSettings: buildCaptureWebViewSettings(),
        // Awaited so the document-start neutraliser is registered BEFORE the
        // initial load starts — a fire-and-forget addUserScript could race
        // the document-start of the 2vcdn page and miss it (reviewer finding
        // 2026-08), silently reintroducing the JS-pause stall.
        onWebViewCreated: (controller) async {
          debugPrint('FILMKU_EXTRACT_HEADLESS webViewCreated');
          try {
            await controller.addUserScript(
              userScript: UserScript(
                source: StreamSourceDataSource.neutralizeAntiFrameScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: true,
              ),
            );
            debugPrint('FILMKU_EXTRACT_HEADLESS antiframeArmed');
          } catch (e) {
            debugPrint('FILMKU_EXTRACT_HEADLESS antiframeError $e');
          }
        },
        // The 2vcdn player refuses to run top-level (`location.replace("/")`
        // anti-frame guard) and the 2embed shell redirects to a DEAD
        // 2embed.cc embed — cancel both so the JW player (and its .m3u8
        // requests) actually load during headless extraction.
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          final target = navigationAction.request.url;
          if (target != null &&
              StreamSourceDataSource.isTwoEmbedKillerNavigation(
                  target.toString())) {
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
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
          final u = request.url.toString();
          // The disable-devtool anti-debug script kills 2embed's player on iOS
          // WKWebView (false-positive redirect to a 404) — answer it with an
          // empty 204 so the page's player runs normally.
          if (StreamSourceDataSource.isDisableDevtoolUrl(u)) {
            return WebResourceResponse(
              contentType: 'text/plain',
              contentEncoding: 'utf-8',
              statusCode: 204,
              reasonPhrase: 'Blocked by FilmKU',
              data: Uint8List(0),
            );
          }
          capture(u);
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
        // Same interception-enabled settings as the real extractor so the
        // sanity check exercises the exact configuration extraction uses.
        initialSettings: buildCaptureWebViewSettings(),
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
        // keep URLs whose path actually ends in .m3u8/.mp4 AND that are not
        // doomed empty `headers={}` templates (substring matching would let
        // script/API URLs through and then fail to play).
        final hit = candidates
            .where(StreamSourceDataSource.isDirectPlayableUrl)
            .toList();
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
/// NATIVE extraction is now the FAST PATH (v1.3.11): the shell resolves to
/// `2vcdn.skin/e/{sid}`, whose packed player config embeds the direct
/// `/stream/.../master.m3u8` — decoded over plain HTTP (no WebView) and
/// served through [HlsRelay] which strips the fake-PNG segment wrapper, so
/// mpv/media_kit plays it natively on iOS AND Android. The old JS-rendered
/// `/swish` headless-scrape path remains only as a fallback.
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
  Future<VideoSource?> extract(int tmdbId, {required bool useHeadless}) async {
    final shell = buildEmbedUrl(tmdbId);
    if (shell == null) return null;
    // Resolve the ad shell to its direct JW-player URL (`2vcdn.skin/e/{sid}`)
    // via plain HTTP (no WebView). The player page serves plain .m3u8 on its
    // own CDN and strips its own ads, so extraction (and later mpv) finally
    // has a real target instead of a shell that redirects to dead 2embed.cc.
    final playerUrl =
        await StreamSourceDataSource.fetchTwoEmbedPlayerUrl(shell);
    final target = playerUrl ?? shell;
    debugPrint(
      'FILMKU_EXTRACT_TRY sourceId=$sourceId label=$label '
      'playerUrl=${playerUrl ?? 'none'} target=$target',
    );

    // FAST PATH (native, no WebView, works identically on iOS + Android):
    // decode the packed player config over plain HTTP and get the direct
    // `/stream/.../master.m3u8` URL, then serve it through the local HLS
    // relay which strips the fake-PNG wrapper from every segment. This is the
    // 2026-08 on-device evidence fix: the JW player never ran in the iOS
    // WebView (JS-pause on cancelled navigation), so WebView-based capture
    // could never see the stream — but the URL itself was always there.
    //
    // ONLY for the legacy 2vcdn chain: the NEW vnest player (2026-08
    // rotation) is a browser-only Next.js → VidNest chain with no direct
    // m3u8, so trying to unpack its page would just burn the 8s timeout.
    if (playerUrl != null && playerUrl.contains('2vcdn.skin')) {
      final direct =
          await StreamSourceDataSource.fetchTwoVcdnStreamUrl(playerUrl);
      if (direct != null) {
        final relayUrl = await HlsRelay.instance.serve(direct);
        debugPrint(
          'FILMKU_EXTRACT_TRY sourceId=$sourceId label=$label '
          'twoVcdnDirect=$direct relay=${relayUrl ?? 'failed'}',
        );
        if (relayUrl != null) {
          return VideoSource(
            sourceId: sourceId,
            label: label,
            videoUrl: relayUrl,
            embedUrl: shell,
            quality: 'Auto',
          );
        }
      }
    }

    return _ScrapeHelper.tryExtract(
      sourceId,
      label,
      target,
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

  /// Whether [url] is a genuinely replayable direct stream URL.
  ///
  /// [shouldCaptureUrl] only checks the media extension. Some signed CDN URLs
  /// additionally carry a `headers=` QUERY TEMPLATE that the player fills with
  /// the real session headers right before requesting (VidLink:
  /// `...mp4?sign=...&headers=%7B%7D&host=...`). An EMPTY template
  /// (`headers={}` / `headers=%7B%7D`) is rejected by the CDN with HTTP 428
  /// when replayed outside the page (mpv) — verified 2026-08 against the
  /// VidLink CDN (`noir.suubmon.store`): 428 with app headers, 403 plain,
  /// and the browser itself hits 428 on many requests. Treating such URLs as
  /// non-playable lets the pipeline fall through to the WebView path, which
  /// captures the FILLED request URL that mpv CAN replay.
  static bool isDirectPlayableUrl(String url) {
    if (!shouldCaptureUrl(url)) return false;
    final query = Uri.tryParse(url)?.query ?? '';
    if (!RegExp(r'headers=', caseSensitive: false).hasMatch(query)) {
      return true;
    }
    // Percent-encoding hex is case-insensitive (%7b%7d == %7B%7D) and
    // encoders vary — normalize to lowercase before the empty-template check.
    final lower = query.toLowerCase();
    return !(lower.contains('headers=%7b%7d') || lower.contains('headers={}'));
  }

  /// Neutralises the 2embed anti-framing guards at the JS level, BEFORE the
  /// page's own script runs (inject at document-start, top frame only):
  ///
  /// - `2vcdn.skin/e/{sid}`: `if(window==window.top) location.replace("/")`
  ///   — the JW player only runs when this redirect is stopped.
  /// - `streamsrcs.2embed.cc/vnest`: `location.replace("https://www.2embed.cc/")
  ///   ` — the NEW 2026-08 chain guard; same mechanism, different target.
  ///
  /// On-device evidence (2026-08, iOS): cancelling these navigations in
  /// `shouldOverrideUrlLoading` makes the page LOAD (LOADSTOP fires) but the
  /// player never requests its `.m3u8` — WKWebView pauses the page's JS
  /// when a top-level navigation is initiated, so the player setup never
  /// executes. Overriding `Location.prototype.replace` to no-op the guard
  /// redirects means the guard never initiates a navigation at all: the page
  /// stays top-level, its JS runs uninterrupted, and the player requests the
  /// playlist like the framed (proven) case. The `shouldOverrideUrlLoading`
  /// cancel is kept as a belt-and-suspenders for engines where the override
  /// fails.
  static const String neutralizeAntiFrameScript = '(function(){'
      'if(window!==window.top)return;'
      'try{var L=Location.prototype;'
      'if(L&&!window.__filmkuAntiFrame){'
      'window.__filmkuAntiFrame=true;'
      'var o=L.replace;'
      'L.replace=function(u){'
      'var s=String(u||"");'
      'if(s==="/"||s==="")return;'
      // Only the BARE-ROOT guard redirect (`https://www.2embed.cc/`) is
      // no-op'd — a real embed navigation (`/embed/movie/{id}`) must still
      // proceed (first-slash heuristics wrongly match `https://` itself).
      r'if(/^https?:\/\/(www\.)?2embed\.cc\/?$/i.test(s))return;'
      'return o.apply(this,arguments);};}'
      '}catch(e){}}})();';

  /// Whether [url] is a 2Embed shell page whose player must be resolved
  /// before the WebView loads it (both the `.skin` AND legacy `.cc` domains
  /// serve the same rotating `swish`/`vnest` chain — 2026-08 evidence).
  static bool isTwoEmbedShellUrl(String url) =>
      url.contains('2embed.skin') || url.contains('2embed.cc');

  /// Whether a URL is a local HLS relay URL produced by [HlsRelay.serve]
  /// (`http://127.0.0.1:{port}/master.m3u8?src={original}`).
  ///
  /// These URLs are SESSION-SCOPED: the relay server binds a random loopback
  /// port and is disposed when playback stops, so a cached relay URL is only
  /// valid while that relay is alive. [PlayerScreen] re-serves cached relay
  /// URLs before playback so a replayed movie never hits a dead port (2026-08:
  /// closing a movie then replaying it failed with "no playable stream found"
  /// until a force-quit cleared the provider cache).
  static bool isRelayUrl(String url) {
    if (!url.startsWith('http://127.0.0.1:')) return false;
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.path.endsWith('.m3u8') &&
        uri.queryParameters.containsKey('src');
  }

  /// Extracts the ORIGINAL CDN URL a relay URL proxies for, or null when
  /// [relayUrl] is not a relay URL (no `src` query).
  static String? relaySourceOf(String relayUrl) {
    final uri = Uri.tryParse(relayUrl);
    if (uri == null) return null;
    final src = uri.queryParameters['src'];
    return (src == null || src.isEmpty) ? null : src;
  }

  /// Whether a URL belongs to the `disable-devtool` anti-debug script or its
  /// 404-redirect host (`theajack.github.io`).
  ///
  /// On-device evidence (2026-08, iOS): 2embed.skin's player pages load
  /// `disable-devtool`, which FALSE-POSITIVES "devtools opened" in a WKWebView
  /// (iOS `innerWidth`/`outerWidth` differ in landscape/immersive) and
  /// redirects the page to a 404 — killing the player so the capture never
  /// sees the stream. Blocking the script lets the player run normally.
  static bool isDisableDevtoolUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('disable-devtool') || lower.contains('theajack');
  }

  /// Extracts the 2embed player session id (`sid`) from the shell page HTML.
  ///
  /// The 2embed.skin shell (`/embed/movie/{id}`) historically embedded its
  /// real player with `data-src="https://streamsrcs.2embed.cc/swish?id={sid}
  /// &ref=mdrct"`, whose player lived at `2vcdn.skin/e/{sid}` (JW Player) and
  /// served plain `.m3u8` playlists on `2vcdn.skin/stream/...`. Loading the
  /// player URL DIRECTLY bypassed the ad shell, its disable-devtool script and
  /// its dead `2embed.cc` redirect — the original iOS native-playback fix.
  ///
  /// ⚠️ 2026-08: the 2Embed ecosystem ROTATED the shell to a new chain
  /// (`streamsrcs.2embed.cc/vnest?tmdb={id}` → `cineby.hair/movie/{id}` →
  /// VidNest) which no longer exposes a `swish` sid and does not serve a
  /// direct m3u8 — see [buildTwoEmbedVnestUrl]. This parser is kept for the
  /// day the backend rotates back (or serves both structures).
  static String? resolveTwoEmbedSwishId(String shellHtml) {
    final cleaned = decodeHtmlEntities(shellHtml);
    final match = RegExp(
      r'data-src="[^"]*streamsrcs[.]2embed[.]cc/swish[?]id=([a-zA-Z0-9_-]+)',
      caseSensitive: false,
    ).firstMatch(cleaned);
    return match?.group(1);
  }

  /// Builds the direct JW-player URL for a 2embed.skin shell page, or null
  /// when the shell does not expose its swish id (no data-src / parse
  /// failure).
  static String? buildTwoEmbedPlayerUrl(String shellHtml) {
    final sid = resolveTwoEmbedSwishId(shellHtml);
    if (sid == null || sid.isEmpty) return null;
    return 'https://2vcdn.skin/e/$sid';
  }

  /// Extracts the TMDB id from the NEW 2embed shell structure
  /// (`data-src="https://streamsrcs.2embed.cc/vnest?tmdb={id}"`).
  ///
  /// 2026-08 rotation: the shell swapped `swish?id={sid}` for
  /// `vnest?tmdb={id}` (verified across desktop/mobile/iOS user-agents). The
  /// vnest page's `vnest.js` then rewrites its player iframe to
  /// `https://cineby.hair/movie/{tmdb}?autostart=true` — a browser-only
  /// (Next.js → VidNest) player with NO direct m3u8, so this never feeds the
  /// native fast path; it only tells the visible WebView which player page to
  /// load directly instead of the dead `swish` shell.
  static String? resolveTwoEmbedVnestTmdb(String shellHtml) {
    final cleaned = decodeHtmlEntities(shellHtml);
    final match = RegExp(
      r'data-src="[^"]*streamsrcs[.]2embed[.]cc/vnest[?]tmdb=([0-9]+)',
      caseSensitive: false,
    ).firstMatch(cleaned);
    return match?.group(1);
  }

  /// Builds the direct vnest player page URL for a 2embed.skin shell page
  /// (`https://streamsrcs.2embed.cc/vnest?tmdb={id}`), or null when the shell
  /// does not expose the new vnest structure.
  static String? buildTwoEmbedVnestUrl(String shellHtml) {
    final tmdb = resolveTwoEmbedVnestTmdb(shellHtml);
    if (tmdb == null || tmdb.isEmpty) return null;
    return 'https://streamsrcs.2embed.cc/vnest?tmdb=$tmdb';
  }

  /// Fetches the 2embed.skin shell page for [embedUrl] (plain HTTP — no
  /// WebView needed) and resolves the player page to load INSTEAD of the
  /// shell: the legacy `2vcdn.skin/e/{sid}` JW player when the shell still
  /// exposes a swish id, or the NEW `streamsrcs.2embed.cc/vnest?tmdb={id}`
  /// player when the shell has rotated. Null on any failure (unreachable
  /// shell / neither structure present).
  static Future<String?> fetchTwoEmbedPlayerUrl(String embedUrl) async {
    final match = RegExp(r'/embed/movie/([0-9]+)').firstMatch(embedUrl);
    if (match == null) return null;
    try {
      // Hard 8s cap: a hanging shell must never starve the capture budget
      // (the first auto-capture provider only gets 30s) or hold the visible
      // WebView's resolution gate open forever.
      final html =
          await _HtmlFetcher.get(embedUrl).timeout(const Duration(seconds: 8));
      // Legacy chain first (direct m3u8, native-playable); then the new
      // vnest chain (browser-only, but the correct WebView target).
      return buildTwoEmbedPlayerUrl(html) ?? buildTwoEmbedVnestUrl(html);
    } catch (_) {
      return null;
    }
  }

  /// -------------------------------------------------------------------------
  /// 2vcdn.skin DIRECT stream extraction (no WebView, no JS execution)
  /// -------------------------------------------------------------------------
  ///
  /// The 2vcdn player page (`2vcdn.skin/e/{sid}`) embeds its real stream URL
  /// as a RELATIVE path inside a Dean-Edwards-packed script:
  ///
  ///   file: "/stream/{t1}/{t2}/{ts}/{fileId}/master.m3u8"
  ///
  /// (verified 2026-08: the tokens are literal entries of the packer's key
  /// array, and the URL serves a valid HLS master playlist over plain HTTP).
  /// No headless WebView / JS execution is needed — decode the packer, regex
  /// the path, and hand `https://2vcdn.skin{path}` to [HlsRelay] which strips
  /// the fake-PNG wrapper from each segment so mpv/media_kit plays it
  /// natively. This is THE iOS/Android native-playback fix for 2Embed.

  /// Un-escapes a JS single-quoted string (`\\` -> `\`, `\'` -> `'`, `\xNN`,
  /// `\uNNNN`, ...) as emitted by the packer's payload argument.
  @visibleForTesting
  static String jsUnescape(String s) {
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (ch == '\\' && i + 1 < s.length) {
        final nxt = s[i + 1];
        // Fixed-width escapes consume their own length; every other escape
        // advances by exactly 2. Rewritten as if/else so each branch
        // explicitly controls `i` (no implicit switch fall-through relied on).
        if (nxt == 'x' && i + 3 < s.length) {
          final code = int.tryParse(s.substring(i + 2, i + 4), radix: 16);
          out.write(String.fromCharCode(code ?? 0x3F));
          i += 4;
        } else if (nxt == 'u' && i + 5 < s.length) {
          final code = int.tryParse(s.substring(i + 2, i + 6), radix: 16);
          out.write(String.fromCharCode(code ?? 0x3F));
          i += 6;
        } else {
          switch (nxt) {
            case '\\':
              out.write('\\');
            case "'":
              out.write("'");
            case '"':
              out.write('"');
            case 'n':
              out.write('\n');
            case 't':
              out.write('\t');
            case 'r':
              out.write('\r');
            default:
              out.write(nxt);
          }
          i += 2;
        }
      } else {
        out.write(ch);
        i++;
      }
    }
    return out.toString();
  }

  /// Converts a decimal number to a base-[radix] string (digits 0-9, a-z,
  /// A-Z) — the token encoding the Dean-Edwards packer uses for key indices.
  ///
  /// The 2vcdn packer uses radix 36 (NOT the classic 62 — verified 2026-08:
  /// token `d4` maps to key index 472 = `vplayer` only in base 36). Using the
  /// wrong radix silently produces wrong tokens, so every call site must pass
  /// the packer's declared radix.
  @visibleForTesting
  static String radixToBase(int num, int radix) {
    const digits =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (num == 0) return '0';
    final out = StringBuffer();
    var n = num;
    while (n > 0) {
      out.write(digits[n % radix]);
      n ~/= radix;
    }
    return out.toString().split('').reversed.join();
  }

  /// Decodes a Dean-Edwards-packed script body (the classic
  /// `eval(function(p,a,c,k,e,d){...}('payload',radix,count,'k0|k1|...'`
  /// format used by the 2vcdn player) into readable JS. Returns null on any
  /// parse failure.
  ///
  /// Robust parse order (reviewer finding 2026-08): the KEY array is located
  /// FIRST (quotes can never appear inside it), then radix/count immediately
  /// before it, then the payload is sliced with `lastIndexOf` up to that
  /// boundary — never with a non-greedy `.*?` over the whole block, which a
  /// payload containing `\',<digits>,<digits>,'` (packed string literals) can
  /// truncate early.
  @visibleForTesting
  static String? unpackDeanEdwards(String packedBlock) {
    // 1. Keys: `...'k0|k1|...'.split('|'))` — quotes cannot appear inside.
    final keysM = RegExp(r"'([^']*)'\.split\('\|'\)\)", dotAll: true)
        .firstMatch(packedBlock);
    if (keysM == null) return null;
    final keysStr = keysM.group(1)!;

    // 2. radix + count immediately before the keys: `,radix,count,'keys'`.
    final metaM = RegExp(
      r",(\d+),(\d+),'" + RegExp.escape(keysStr) + r"'\.split",
    ).firstMatch(packedBlock);
    if (metaM == null) return null;
    final radix = int.tryParse(metaM.group(1)!) ?? 36;
    final count = int.tryParse(metaM.group(2)!) ?? 0;

    // 3. Payload: everything between `return p}(` and the `',radix,count,'`
    // boundary (lastIndexOf so an identical-looking fragment inside the
    // payload never wins).
    const open = 'return p}(';
    final openIdx = packedBlock.indexOf(open);
    // Boundary is `,radix,count,'keys'` — NO quote after the first comma
    // (a stray `,'$radix...` would never match the real `,36,490,'keys`
    // format and silently return null).
    final boundary = ",$radix,$count,'$keysStr'";
    final bodyEnd = packedBlock.lastIndexOf(boundary);
    if (openIdx < 0 || bodyEnd <= openIdx + open.length) return null;
    // The payload literal is sliced WITH its wrapping single-quotes (the
    // boundary is the `',radix,count,'keys'` terminator), so strip them — the
    // old non-greedy regex captured the payload without them. Escaped quotes
    // inside (`\'`) are already unescaped by jsUnescape before this strip, so
    // only the true wrapper is removed.
    var body =
        jsUnescape(packedBlock.substring(openIdx + open.length, bodyEnd));
    if (body.startsWith("'") && body.endsWith("'")) {
      body = body.substring(1, body.length - 1);
    }

    var keys = keysStr.split('|');
    while (keys.length < count) {
      keys = [...keys, ''];
    }
    // Substitute indices from the highest down (the original loop) so earlier
    // keys never corrupt already-substituted text.
    for (var c = count - 1; c >= 0; c--) {
      if (c >= keys.length) continue;
      final k = keys[c];
      if (k.isEmpty) continue;
      final token = radixToBase(c, radix);
      final pattern =
          RegExp('(?<![A-Za-z0-9_])${RegExp.escape(token)}(?![A-Za-z0-9_])');
      body = body.replaceAll(pattern, k);
    }
    return body;
  }

  /// Extracts the `/stream/{tokens}/master.m3u8` path from an unpacked 2vcdn
  /// player script body, or null when absent.
  @visibleForTesting
  static String? extractTwoVcdnStreamPath(String unpackedBody) {
    final m = RegExp(
      r'(/stream/[A-Za-z0-9_/-]+/master[.]m3u8)',
    ).firstMatch(unpackedBody);
    return m?.group(1);
  }

  /// Extracts the direct stream URL from a raw 2vcdn player page.
  ///
  /// Returns `https://2vcdn.skin{path}` or null when the page has no packer
  /// or no stream path. Pure HTTP — no WebView, no JS.
  static String? streamUrlFromTwoVcdnPage(String pageHtml) {
    final packedStart = pageHtml.indexOf('eval(function(p,a,c,k,e,d)');
    if (packedStart < 0) return null;
    final unpacked = unpackDeanEdwards(pageHtml.substring(packedStart));
    if (unpacked == null) return null;
    final path = extractTwoVcdnStreamPath(unpacked);
    if (path == null) return null;
    return 'https://2vcdn.skin$path';
  }

  /// Fetches the 2vcdn player page for [playerUrl] (`2vcdn.skin/e/{sid}`) and
  /// returns its direct `.m3u8` stream URL, or null on any failure. Hard 8s
  /// cap so a hanging page never starves the extraction budget.
  static Future<String?> fetchTwoVcdnStreamUrl(String playerUrl) async {
    try {
      final html =
          await _HtmlFetcher.get(playerUrl).timeout(const Duration(seconds: 8));
      return streamUrlFromTwoVcdnPage(html);
    } catch (_) {
      return null;
    }
  }

  /// Whether a navigation should be cancelled inside a 2embed capture WebView:
  /// - `2vcdn.skin/` — the JW player's own anti-framing
  ///   `location.replace("/")` (`if(window==window.top)`); the player ONLY
  ///   runs when this redirect is stopped (verified headless 2026-08: the
  ///   framed load requested the m3u8, the top-level load redirected to `/`).
  /// - `www.2embed.cc/` — the NEW (2026-08) vnest chain's anti-frame guard
  ///   (`location.replace("https://www.2embed.cc/")`); same mechanism, dead
  ///   landing.
  /// - any `2embed` host navigating to `/movie/movie/` — the shell's redirect
  ///   to the DEAD `2embed.cc` embed that cancels the player iframe on iOS
  ///   (NSURLError -999, v1.3.8 syslog).
  static bool isTwoEmbedKillerNavigation(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return false;
    final host = uri.host.toLowerCase();
    final path = uri.path;
    if (host == '2vcdn.skin' && (path.isEmpty || path == '/')) return true;
    // The vnest anti-frame guard redirects to the bare `2embed.cc` root (with
    // or without `www`, no path). The REAL 2embed.cc embed pages
    // (`/embed/movie/{id}`) keep their path and must NOT be cancelled.
    if ((host == 'www.2embed.cc' || host == '2embed.cc') &&
        (path.isEmpty || path == '/')) {
      return true;
    }
    if (host.contains('2embed') && path.contains('/movie/movie/')) return true;
    return false;
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
