import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/webview/capture_webview_settings.dart';
import '../../data/datasources/stream_source_datasource.dart';
import 'stream_capture_core.dart';

/// WebView that loads a source embed page and captures the direct media URL
/// its player requests (network interception + the all-frames relay + DOM
/// probe), then reports it once via [onCaptured].
///
/// Used by [PlayerScreen] so playback can jump straight into the native
/// (libmpv) player WITHOUT the user ever seeing the WebView or its ads: the
/// player screen paints an OPAQUE overlay on top of this full-size WebView,
/// so the user only sees a spinner while the capture happens behind it.
///
/// IMPORTANT (on-device diagnosis 2026-08, Xiaomi/MIUI): this WebView MUST
/// be a genuinely VISIBLE Android view. Two earlier "hiding" approaches both
/// failed: `Opacity(opacity: 0)` (platform view never attaches its surface →
/// page never loads) and off-screen `Positioned(left: -10000)` (page LOADS —
/// LOADSTOP fires — but the source's player never starts, so the m3u8 is
/// never requested and capture times out). Only a normally-visible WebView
/// (like the manual fallback, which captures the same source in ~7s) makes
/// the embed player autoplay and request its stream. Hiding from the USER is
/// done by the parent's opaque overlay PAINT — that does not change the
/// platform view's actual visibility, so the player behaves normally.
class HiddenStreamCapture extends StatefulWidget {
  const HiddenStreamCapture({
    super.key,
    required this.url,
    required this.sourceLabel,
    required this.onCaptured,
    required this.onTimeout,
    this.timeout = const Duration(seconds: 25),
  });

  /// Static web-resource extensions (scripts, styles, images, fonts, JSON).
  /// A URL ending in one of these is NEVER the stream CDN — used by the
  /// early-abort to ignore tracker/analytics noise that fails on the user's
  /// ISP (cloudflareinsights, google-analytics, … all fail with
  /// ERR_CONNECTION_REFUSED too). Exposed for tests.
  @visibleForTesting
  static bool isStaticAssetUrl(String url) {
    final path = url.toLowerCase().split('?').first.split('#').first;
    const extensions = <String>[
      '.js',
      '.css',
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.svg',
      '.webp',
      '.ico',
      '.woff',
      '.woff2',
      '.ttf',
      '.json',
      '.xml',
      '.map',
      '.txt',
    ];
    return extensions.any(path.endsWith);
  }

  /// Whether an error is a network-level failure (connection refused / DNS /
  /// reset / TLS) — the signature of a blocked or dead CDN — as opposed to a
  /// content error (404/403, decode failure) that ad/tracker hosts produce
  /// constantly. Exposed for tests.
  @visibleForTesting
  static bool isFatalNetworkError(String typeName) {
    return typeName.contains('CANNOT_CONNECT_TO_HOST') ||
        typeName.contains('HOST_LOOKUP') ||
        typeName.contains('NETWORK_CONNECTION_LOST') ||
        typeName.contains('CONNECTION_ABORTED') ||
        typeName.contains('NOT_CONNECTED_TO_INTERNET') ||
        typeName.contains('FAILED_SSL_HANDSHAKE');
  }

  /// Normalizes a failed-request URL to the CDN identity used as the failure
  /// counter key: scheme + authority + path, with any query string or fragment
  /// stripped. Signed CDN URLs rotate their token on every retry
  /// (VidLink-style `?sign=...&t=...`), so counting the FULL URL would never
  /// accumulate — the early abort would never fire on exactly the dead-CDN
  /// case it targets. Exposed for tests.
  @visibleForTesting
  static String cdnFailureKey(String url) {
    final uri = Uri.tryParse(url);
    // Missing scheme/authority (e.g. `about:blank`, empty) → leave untouched:
    // onReceivedError can fire for non-http(s) requests and those must never
    // be transformed into a synthetic `scheme://authority/path` key.
    if (uri == null || uri.scheme.isEmpty || !uri.hasAuthority) return url;
    final path = uri.path;
    if (path.isEmpty) return '${uri.scheme}://${uri.authority}';
    return '${uri.scheme}://${uri.authority}$path';
  }

  /// Records one failure for a CDN identity [key] and returns the new running
  /// count for that key. Exposed for tests.
  @visibleForTesting
  static int recordFailure(Map<String, int> failures, String key) {
    final next = (failures[key] ?? 0) + 1;
    failures[key] = next;
    return next;
  }

  /// Repeated failures of the SAME non-static, non-ad URL that trigger an
  /// early abort of the current provider. On-device evidence (2026-08):
  /// vidsrc.to's tokenized stream CDN is refused (`ERR_CONNECTION_REFUSED` /
  /// `ERR_NAME_NOT_RESOLVED`) and the player retries the same URL ~every 3s —
  /// so 3 failures ≈ 7s instead of the full 30s budget. Ad/tracker URLs are
  /// excluded (static assets + ad hosts), so a legitimately-working provider
  /// with a few broken ad networks is never aborted. Exposed for tests.
  static const int earlyAbortFailureThreshold = 3;

  /// Whether [failureCount] for a URL has reached [earlyAbortFailureThreshold].
  /// Exposed for tests.
  @visibleForTesting
  static bool shouldEarlyAbort(int failureCount) =>
      failureCount >= earlyAbortFailureThreshold;

  /// Consecutive rejections of the SAME non-directly-playable URL that make
  /// the capture give up on this provider (fail fast to the next one).
  ///
  /// On-device evidence (2026-08, iOS): VidLink's signed URL carries an EMPTY
  /// `headers={}` query template that the player NEVER fills — the browser
  /// itself requests it empty (netlog-verified) — so the capture keeps
  /// re-reading the same unplayable URL on every probe and would burn the
  /// full budget waiting for a filled URL that never comes. Two consecutive
  /// rejections (~4s of probes) mean this provider can only be watched in a
  /// real browser (visible WebView), not natively — skip it.
  static const int nonPlayableGiveUpThreshold = 2;

  /// Whether [consecutiveRejections] of the same unplayable URL have reached
  /// [nonPlayableGiveUpThreshold]. Exposed for tests.
  @visibleForTesting
  static bool shouldGiveUpOnNonPlayable(int consecutiveRejections) =>
      consecutiveRejections >= nonPlayableGiveUpThreshold;

  /// The embed page to load (e.g. `https://vidsrc.to/embed/movie/123`).
  final String url;

  /// Human-readable provider name (used in diagnostics logs).
  final String sourceLabel;

  /// Called once with the discovered direct stream URL.
  final ValueChanged<WebViewNativeStream> onCaptured;

  /// Called if no stream is captured within [timeout].
  final VoidCallback onTimeout;

  final Duration timeout;

  @override
  State<HiddenStreamCapture> createState() => _HiddenStreamCaptureState();
}

class _HiddenStreamCaptureState extends State<HiddenStreamCapture> {
  InAppWebViewController? _controller;
  Timer? _probeTimer;
  Timer? _timeoutTimer;
  WebViewNativeStream? _captured;

  /// URL → repeated network-failure count for the early CDN-block abort.
  /// Fresh per provider because the widget is keyed by provider index.
  final Map<String, int> _fatalFailures = <String, int>{};

  /// Guards against double-abort/double-give-up: once this provider is done
  /// (network-blocked via [_maybeEarlyAbort], or never-natively-playable via
  /// the `_setCaptured` give-up), the WebView can still fire interception
  /// callbacks while the parent swaps in the next provider — a second
  /// `onTimeout()` would advance the provider index twice and SKIP a source.
  bool _earlyAborted = false;

  /// Normalized identity of the last REJECTED (non-directly-playable) URL
  /// and how many times in a row it was rejected. VidLink's signed URL is
  /// re-read on every probe with the same empty `headers={}` template, so
  /// after [HiddenStreamCapture.nonPlayableGiveUpThreshold] consecutive
  /// rejections the capture gives up on this provider instead of burning the
  /// full budget on a URL mpv can never play.
  String _rejectedKey = '';
  int _rejectedCount = 0;

  @override
  void initState() {
    super.initState();
    // Poll for a relayed/captured direct stream URL. The player is created by
    // the source's JS after the page loads, so retry until one is found.
    _probeTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_captured == null) _probe();
    });
    _timeoutTimer = Timer(widget.timeout, () {
      if (_captured == null && mounted) widget.onTimeout();
    });
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _injectAllFramesScript(InAppWebViewController controller) async {
    try {
      await controller.addUserScript(
        userScript: UserScript(
          source: embedAllFramesScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
      );
      // On-device diagnosis (2026-08): the source's player only requests its
      // m3u8 after playback starts (manual capture took ~26s); some players
      // even sit behind a play-button overlay. This second all-frames script
      // programmatically clicks play affordances + calls video.play() so the
      // capture happens within seconds instead of the timeout budget.
      await controller.addUserScript(
        userScript: UserScript(
          source: embedAutoPlayNudgeScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
      );
      debugPrint('FILMKU_AUTOCAPTURE_USERSCRIPT_ADDED');
    } catch (e) {
      debugPrint('FILMKU_AUTOCAPTURE_USERSCRIPT_ERROR $e');
    }
  }

  void _setCaptured(String url, Duration position, {String via = 'probe'}) {
    if (_earlyAborted || _captured != null || !mounted) return;
    if (!embedIsNativeStreamCandidate(url, embedUrl: widget.url)) return;
    // A signed URL with an EMPTY `headers={}` template (VidLink) is rejected
    // by the CDN with HTTP 428 when replayed outside the page — mpv can
    // never play it (verified on-device 2026-08: "Failed to open" 0.5s after
    // open). It is NOT a native capture: hand it to mpv and the screen just
    // bounces back into the WebView. Consecutive rejections of the same
    // (scheme+host+path) URL mean the player will never expose a playable
    // one — fail fast to the next provider (or the visible WebView, which
    // CAN play it in a real browser).
    if (!StreamSourceDataSource.isDirectPlayableUrl(url)) {
      final key = HiddenStreamCapture.cdnFailureKey(url);
      if (key == _rejectedKey) {
        _rejectedCount++;
      } else {
        _rejectedKey = key;
        _rejectedCount = 1;
      }
      debugPrint(
        'FILMKU_AUTOCAPTURE_SKIP_NONPLAYABLE url=$url key=$key '
        'count=$_rejectedCount',
      );
      if (HiddenStreamCapture.shouldGiveUpOnNonPlayable(_rejectedCount)) {
        _earlyAborted = true;
        _probeTimer?.cancel();
        _timeoutTimer?.cancel();
        debugPrint(
          'FILMKU_AUTOCAPTURE_GIVEUP source=${widget.sourceLabel} '
          'url=$url',
        );
        widget.onTimeout();
      }
      return;
    }
    debugPrint(
      'FILMKU_AUTOCAPTURE_CAPTURED via=$via url=$url '
      'posMs=${position.inMilliseconds}',
    );
    setState(() {
      _captured = WebViewNativeStream(url: url, position: position);
    });
    widget.onCaptured(_captured!);
    _probeTimer?.cancel();
    _timeoutTimer?.cancel();
  }

  /// Aborts this provider EARLY when its stream CDN is provably unreachable:
  /// repeated network-level failures (connection refused / DNS / reset) on the
  /// SAME non-static, non-ad URL mean the ISP blocks the CDN — waiting out the
  /// full budget (30s+) is pure waste. Delegates to [onTimeout] so the caller
  /// advances to the next provider (or the visible WebView) immediately.
  ///
  /// Ignored for ad/tracker hosts (blocked on every ISP) and static assets
  /// (scripts/styles/images), so a provider whose player works but whose ad
  /// networks are dead is never aborted.
  void _maybeEarlyAbort({
    required String url,
    required String host,
    required String typeName,
  }) {
    if (_earlyAborted || _captured != null || !mounted) return;
    if (embedIsAdHost(host)) return;
    if (HiddenStreamCapture.isStaticAssetUrl(url)) return;
    if (!HiddenStreamCapture.isFatalNetworkError(typeName)) return;
    // Key by scheme+host+path (NOT the full URL): signed CDN tokens rotate
    // on every retry, so a full-URL key would never accumulate and the
    // dead-CDN abort would never fire (reviewer finding 2026-08).
    final key = HiddenStreamCapture.cdnFailureKey(url);
    final count = HiddenStreamCapture.recordFailure(_fatalFailures, key);
    debugPrint(
      'FILMKU_AUTOCAPTURE_CDN_FAIL url=$url key=$key count=$count '
      'type=$typeName',
    );
    if (HiddenStreamCapture.shouldEarlyAbort(count)) {
      _earlyAborted = true;
      _probeTimer?.cancel();
      _timeoutTimer?.cancel();
      debugPrint(
        'FILMKU_AUTOCAPTURE_EARLY_ABORT source=${widget.sourceLabel} '
        'url=$url failures=$count',
      );
      widget.onTimeout();
    }
  }

  Future<void> _probe() async {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;
    final String raw;
    try {
      raw = (await controller.evaluateJavascript(
            source: embedProbeScript,
          )) ??
          '';
    } catch (_) {
      return; // Page mid-navigation — try again next tick.
    }
    if (raw.isEmpty || raw == 'null') return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final url = decoded['url'];
      if (url is! String || url.isEmpty) return;
      final seconds = decoded['t'];
      final position = Duration(
        milliseconds: ((seconds is num ? seconds : 0) * 1000).round(),
      );
      _setCaptured(url, position);
    } on FormatException {
      // Transient non-JSON eval — try again next tick.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Full-size, gesture-ignoring WebView — genuinely VISIBLE to the Android
    // view system (see the class doc for why hiding it breaks the player).
    // The parent's opaque overlay is painted ON TOP, so the user never sees
    // this WebView or its ads.
    return IgnorePointer(
      ignoring: true,
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        // Interception callbacks (request/fetch/ajax) must be explicitly
        // enabled on iOS (they default to false there, on vs. off on
        // Android) — otherwise the capture never sees the stream URL and
        // times out into the visible WebView. Shared builder keeps every
        // capture WebView consistent. See capture_webview_settings.dart.
        initialSettings: buildCaptureWebViewSettings(),
        onWebViewCreated: (controller) {
          _controller = controller;
          _injectAllFramesScript(controller);
          debugPrint(
            'FILMKU_AUTOCAPTURE_OPEN source=${widget.sourceLabel} '
            'url=${widget.url}',
          );
        },
        // Main-frame navigations to ad landing pages are cancelled.
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          final target = navigationAction.request.url;
          if (target != null && embedIsAdHost(target.host)) {
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        // Ad sub-resources answered with an empty 204; .m3u8/.mp4 media
        // loads are captured for native playback.
        shouldInterceptRequest: (controller, request) async {
          final url = request.url.toString();
          final host = request.url.host;
          if (embedIsAdHost(host)) {
            debugPrint('FILMKU_AUTOCAPTURE_ADBLOCK host=$host');
            return WebResourceResponse(
              contentType: 'text/plain',
              contentEncoding: 'utf-8',
              statusCode: 204,
              reasonPhrase: 'Blocked by FilmKU',
              data: Uint8List(0),
            );
          }
          if (embedIsMediaUrl(url)) {
            _setCaptured(url, Duration.zero, via: 'intercept');
          }
          return null;
        },
        // fetch()/XHR media loads (top-frame JS players). Returning the
        // request unchanged always continues it; we only observe.
        shouldInterceptFetchRequest: (controller, fetchRequest) async {
          final url = fetchRequest.url.toString();
          if (embedIsMediaUrl(url)) {
            _setCaptured(url, Duration.zero, via: 'fetch');
          }
          return fetchRequest;
        },
        shouldInterceptAjaxRequest: (controller, ajaxRequest) async {
          final url = ajaxRequest.url.toString();
          if (embedIsMediaUrl(url)) {
            _setCaptured(url, Duration.zero, via: 'ajax');
          }
          return ajaxRequest;
        },
        // Diagnostics: prove whether the page actually LOADED (the
        // previous on-device failure showed OPEN+USERSCRIPT_ADDED then
        // silence — these logs split "page never loaded" from
        // "page loaded but no media URL").
        onLoadStart: (controller, url) {
          debugPrint('FILMKU_AUTOCAPTURE_LOADSTART url=$url');
        },
        onLoadStop: (controller, url) async {
          debugPrint('FILMKU_AUTOCAPTURE_LOADSTOP url=$url');
          // Re-inject the scripts into the top frame (idempotent) and probe
          // right away instead of waiting for the next tick.
          try {
            await controller.evaluateJavascript(
              source: embedAllFramesScript,
            );
          } catch (_) {}
          // Re-arm the play nudge after each navigation too.
          try {
            await controller.evaluateJavascript(
              source: embedAutoPlayNudgeScript,
            );
          } catch (_) {}
          // The player now genuinely autoplays (it's a visible WebView),
          // so mute top-frame video: the user only sees the spinner overlay
          // and shouldn't hear the movie/ad audio behind it. (Cross-origin
          // iframe players are out of reach here, but mpv takes over within
          // seconds of capture anyway.)
          try {
            await controller.evaluateJavascript(
              source: '(function(){'
                  'document.querySelectorAll("video").forEach('
                  'function(v){v.muted=true;});'
                  'document.addEventListener("play",function(e){'
                  'var v=e.target;if(v&&!v.muted)v.muted=true;},true);'
                  '})();',
            );
          } catch (_) {}
          _probe();
        },
        onReceivedError: (controller, request, error) {
          debugPrint(
            'FILMKU_AUTOCAPTURE_RECVERROR url=${request.url} '
            'type=${error.type} desc=${error.description}',
          );
          _maybeEarlyAbort(
            url: request.url.toString(),
            host: request.url.host,
            typeName: error.type.toString(),
          );
        },
        // Popup/popunder ad windows are blocked — the player runs in
        // this page.
        onCreateWindow: (controller, createWindowAction) async {
          return false;
        },
      ),
    );
  }
}
