import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/webview/capture_webview_settings.dart';
import '../widgets/error_view.dart';
import '../widgets/player_swipe_dismiss.dart';
import '../widgets/stream_capture_core.dart';

export '../widgets/stream_capture_core.dart' show WebViewNativeStream;

/// Arguments for the WebView fallback player route.
class WebViewPlayerArgs {
  const WebViewPlayerArgs({
    required this.url,
    required this.sourceLabel,
    this.autoHandoff = true,
  });

  /// The source embed page (e.g. `https://vidlink.pro/movie/123`).
  final String url;

  /// Human-readable provider name shown in the top bar.
  final String sourceLabel;

  /// When true (default), the screen auto-handoffs to the native player once
  /// the embed player is confirmed playing a stable stream (after a short
  /// countdown with a cancel button). Disabled when returning from a failed
  /// native attempt so the WebView does not bounce straight back into the
  /// native player (loop).
  final bool autoHandoff;
}

/// WebView-based fallback player.
///
/// Some sources (e.g. VidLink) only expose their stream inside a real browser
/// context — the signed `.mp4` URL is unusable by the native player (libmpv,
/// `media_kit`) because the CDN requires cookies / TLS fingerprint / session.
/// Loading the embed page in an in-app WebView plays the source's own player,
/// which already has that context.
///
/// The source's player usually runs inside a **cross-origin iframe** (e.g.
/// 2embed's `streamsrcs.2embed.cc/swish`), so plain top-page JS cannot see
/// its video or its first-party ads. Three layers handle that:
/// 1. **All-frames script** — a `UserScript` (document-start,
///    `forMainFrameOnly: false`, origin rules `*`) is injected into EVERY
///    frame, including cross-origin iframes. It removes ad overlay elements,
///    blocks `window.open`, and relays the playing `<video>` URL + position
///    to the top page via `postMessage`.
/// 2. **Network capture** — `shouldInterceptRequest`/fetch/ajax handlers
///    record any `.m3u8`/`.mp4` the player loads (even from inside iframes),
///    and block known ad/tracker hosts with an empty 204. Navigations to ad
///    landing pages are cancelled.
/// 3. **Native handoff** — once a direct stream URL is known (relay or
///    capture), a "Play natively (ad-free)" button appears; tapping it pops
///    this screen and playback continues in the native player.
class WebViewPlayerScreen extends StatefulWidget {
  const WebViewPlayerScreen({super.key, required this.args});

  final WebViewPlayerArgs args;

  /// Decides whether a WebView load error should surface as a full-screen
  /// failure. Sub-frame errors (ads/trackers) fire constantly on these source
  /// pages — surfacing them would cover the still-playing video with a fake
  /// "failed to load" UI. Only a failure of the original embed document (the
  /// main frame at the exact URL we were asked to load) may fail the player.
  /// Exposed for tests.
  @visibleForTesting
  static bool shouldSurfaceLoadError({
    required bool? isForMainFrame,
    required String requestUrl,
    required String expectedUrl,
  }) =>
      isForMainFrame == true && requestUrl == expectedUrl;

  /// Decides whether an HTTP error should surface: only for the main document
  /// AND only when the request URL is the original embed URL (after a
  /// redirect, e.g. vidsrc.to → vsembed.ru, the source's own page — with its
  /// own error UI — is shown instead). Same rule as [shouldSurfaceLoadError],
  /// kept as a separate name for call-site clarity. Exposed for tests.
  @visibleForTesting
  static bool shouldSurfaceHttpError({
    required bool? isForMainFrame,
    required String requestUrl,
    required String expectedUrl,
  }) =>
      shouldSurfaceLoadError(
        isForMainFrame: isForMainFrame,
        requestUrl: requestUrl,
        expectedUrl: expectedUrl,
      );

  /// Host fragments of known ad/tracker networks (shared with the hidden
  /// auto-capture). Exposed for tests.
  static const List<String> _adHostFragments = embedAdHostFragments;

  /// Whether a request host targets a known ad network. Exposed for tests.
  @visibleForTesting
  static bool isAdHost(String host) =>
      _adHostFragments.any((fragment) => host.contains(fragment));

  /// Whether a `<video>` URL discovered in the WebView can be handed off to
  /// the native player. Delegates to the shared [embedIsNativeStreamCandidate]
  /// (also used by the hidden auto-capture). Exposed for tests.
  @visibleForTesting
  static bool isNativeStreamCandidate(String url, {required String embedUrl}) =>
      embedIsNativeStreamCandidate(url, embedUrl: embedUrl);

  /// Whether a network request URL is a direct media manifest/file worth
  /// capturing. Delegates to the shared [embedIsMediaUrl]. Exposed for tests.
  @visibleForTesting
  static bool isMediaUrl(String url) => embedIsMediaUrl(url);

  /// Consecutive probes (each ~2s apart) that must report a BLANK document
  /// before the screen gives up. Some sources (e.g. 2embed.cc in certain
  /// regions) serve `about:blank` — a white screen with no player, which the
  /// native handoff can never resolve. After this many blank probes the
  /// WebView pops back so [PlayerScreen] can auto-failover to the next
  /// provider instead of stranding the user on white. Exposed for tests.
  static const int blankProbeThreshold = 3;

  /// Whether a probe payload reports a blank document (about:blank URL or an
  /// empty body). Exposed for tests.
  @visibleForTesting
  static bool isBlankProbe(Map<String, dynamic> decoded) =>
      decoded['blank'] == true;

  /// Whether [consecutiveBlankProbes] has reached [blankProbeThreshold].
  /// Exposed for tests.
  @visibleForTesting
  static bool shouldSurfaceBlankError(int consecutiveBlankProbes) =>
      consecutiveBlankProbes >= blankProbeThreshold;

  /// Consecutive probes (each ~2s apart) that must show ADVANCING playback
  /// before the auto-handoff countdown starts. Exposed for tests.
  static const int stableProbeThreshold = 3;

  /// Seconds of the auto-handoff countdown shown before the screen pops into
  /// the native player. Exposed for tests.
  static const int autoHandoffCountdownSeconds = 5;

  /// Advances the stable-probe counter: returns [count] + 1 when [position]
  /// is strictly ahead of [lastPosition] (playback is genuinely progressing),
  /// otherwise resets to 0 (paused/buffering/restart). Used by the
  /// auto-handoff — a stream is only handed to the native player once it has
  /// played stably for [stableProbeThreshold] consecutive probes. Exposed for
  /// tests.
  @visibleForTesting
  static int advanceStableProbe({
    required Duration position,
    required Duration lastPosition,
    required int count,
  }) {
    if (position <= lastPosition) return 0;
    return count + 1;
  }

  /// Injected at document-start into EVERY frame (including cross-origin
  /// iframes) via `addUserScript(forMainFrameOnly: false)`, and re-injected
  /// into the top frame after each load via `evaluateJavascript` (idempotent
  /// guard `__filmkuA`):
  /// - removes ad overlay elements (class/id match) and ad-host iframes,
  /// - blocks `window.open` popups,
  /// - relays the playing `<video>` URL + time to the top page via
  ///   `postMessage({__filmku: {url, t}})` (MSE `blob:` URLs are skipped —
  ///   they cannot play natively),
  /// - the top frame stores the relayed value in `window.__filmku` for Dart
  ///   polling.
  static const String _allFramesJs = '(function(){'
      'if(window.__filmkuA)return;window.__filmkuA=true;'
      'var ADRE=/(^|[-_ ])(ad|ads|advert|banner|popup|popunder|overlay|sponsor)([-_ ]|\$)/i;'
      'var SKIPRE=/player|video|movie|jw|plyr|menu|quality|setting|control|modal/i;'
      'function adlike(e){if(!e||e.nodeType!==1)return false;'
      'var s=(e.id||"")+" "+(typeof e.className==="string"?e.className:"");'
      'if(!ADRE.test(s))return false;if(SKIPRE.test(s))return false;'
      'if(e.querySelector&&e.querySelector("video"))return false;return true;}'
      'function kill(e){try{'
      'if(adlike(e)){if(e.parentNode){e.parentNode.removeChild(e);'
      'try{window.parent.postMessage({__filmkuAd:1},"*");}catch(err){}}'
      'return;}'
      'if(e.querySelectorAll){var f=e.querySelectorAll("iframe");'
      'for(var i=0;i<f.length;i++){var src=f[i].getAttribute("src")||"";'
      'if(/doubleclick|googlesyndication|popads|popcash|taboola|outbrain|propellerads|adsterra|adcash|exoclick/i.test(src)){'
      'if(f[i].parentNode){f[i].parentNode.removeChild(f[i]);'
      'try{window.parent.postMessage({__filmkuAd:1},"*");}catch(err){}}}}'
      '}catch(err){}}'
      'if(window.MutationObserver){new MutationObserver(function(m){'
      'for(var i=0;i<m.length;i++){var n=m[i].addedNodes;'
      'for(var j=0;j<n.length;j++){if(n[j]&&n[j].nodeType===1)kill(n[j]);}}'
      '}).observe(document.documentElement,{childList:true,subtree:true});}'
      'setInterval(function(){var a=document.querySelectorAll("div,iframe");'
      'for(var i=0;i<a.length;i++)kill(a[i]);},2500);'
      'try{window.open=function(){return null;};}catch(err){}'
      'function report(){try{var v=document.querySelector("video");'
      'if(!v)return;var u=v.currentSrc||v.src||"";'
      'if(!u||u.indexOf("blob:")===0)return;'
      'window.parent.postMessage({__filmku:{url:u,t:v.currentTime||0}},"*");'
      '}catch(err){}}'
      'setInterval(report,1200);'
      'document.addEventListener("play",report,true);'
      'if(window===window.top){window.__filmku=null;window.__filmkuAds=0;'
      'window.addEventListener("message",function(ev){'
      'var d=ev.data;if(d&&d.__filmku&&d.__filmku.url)window.__filmku=d.__filmku;'
      'if(d&&d.__filmkuAd){window.__filmkuAds=(window.__filmkuAds||0)+1;}});}'
      '})();';

  /// Reads the relayed video (from any frame) or, as a fallback, a top-frame
  /// `<video>` directly, plus the JS-side ad-strip counter. Returns
  /// `JSON.stringify({url, t, ads, blank})` (url may be `''` when nothing
  /// plays). `blank` is true when the top document is `about:blank` or has an
  /// empty body — the white-screen signature of a dead/region-blocked source
  /// (e.g. 2embed.cc) that can never produce a native-handoff stream.
  static const String _probeVideoJs = '(function(){'
      'var a=window.__filmkuAds||0;'
      'var blank=(location.href==="about:blank")||(!document.body)||(document.body.childElementCount===0);'
      'var f=window.__filmku;if(f&&f.url)return JSON.stringify({url:f.url,t:f.t||0,ads:a,blank:blank});'
      'var v=document.querySelector("video");'
      'if(v){var u=v.currentSrc||v.src||"";'
      'if(u&&u.indexOf("blob:")!==0&&u.indexOf("http")===0)'
      'return JSON.stringify({url:u,t:v.currentTime||0,ads:a,blank:blank});}'
      'return JSON.stringify({url:"",t:0,ads:a,blank:blank});'
      '})()';

  @override
  State<WebViewPlayerScreen> createState() => _WebViewPlayerScreenState();
}

class _WebViewPlayerScreenState extends State<WebViewPlayerScreen> {
  InAppWebViewController? _controller;
  bool _loading = true;
  String? _error;

  /// True when the current [_error] is an HTTP status error (a real final
  /// state — e.g. a 404 page). Network-level errors are transient during the
  /// redirect chain (vidsrc.to → vsembed.ru) and are cleared by [onLoadStop]
  /// once a main document actually loads, so a stale error never covers the
  /// still-playing video.
  bool _httpError = false;

  /// A direct stream URL discovered inside the embed player, if any.
  WebViewNativeStream? _nativeStream;

  /// How many ads were blocked — network requests (interceptor) plus ad
  /// elements stripped by the injected JS (relayed via `__filmkuAds`). Shown
  /// as a small chip so the user gets instant visible confirmation.
  int _adBlocked = 0;

  /// Last JS-side ad count seen by the probe, used to accumulate deltas.
  int _lastJsAds = 0;

  Timer? _probeTimer;

  /// Auto-handoff stability state.
  int _stableCount = 0;
  Duration _lastProbePosition = Duration.zero;
  bool _handoffPending = false;
  int _countdownLeft = 0;
  Timer? _countdownTimer;

  /// True after the user tapped "Batal" — auto-handoff is not re-armed for
  /// this session (the manual "Play natively" button stays available).
  bool _autoHandoffCancelled = false;

  /// Consecutive probes that reported a blank document; reaches
  /// [WebViewPlayerScreen.blankProbeThreshold] → the screen pops back so the
  /// player can failover to another provider.
  int _blankProbes = 0;

  /// Guards against double-pop when a blank page is detected (probe timers
  /// fire again between the detection and the pop).
  bool _blankEscaped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enterLandscape();
    });
    // Poll for a relayed/captured direct stream URL. The player is created by
    // the source's JS after the page loads, so retry until one is found.
    _probeTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _probeNativeStream();
    });
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
    _countdownTimer?.cancel();
    // NOTE: do NOT dispose the InAppWebViewController here — the InAppWebView
    // widget owns its controller lifecycle; a manual dispose during teardown
    // risks a double-dispose. We keep the reference only for reload().
    _restorePortrait();
    super.dispose();
  }

  Future<void> _enterLandscape() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _restorePortrait() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// Injects the all-frames script at document-start so it also runs inside
  /// cross-origin iframes (the source's actual player). Logs success so the
  /// logcat can confirm the mechanism on any device.
  Future<void> _injectAllFramesScript(InAppWebViewController controller) async {
    try {
      await controller.addUserScript(
        userScript: UserScript(
          source: WebViewPlayerScreen._allFramesJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
      );
      debugPrint('FILMKU_WEBVIEW_USERSCRIPT_ADDED');
    } catch (e) {
      debugPrint('FILMKU_WEBVIEW_USERSCRIPT_ERROR $e');
    }
  }

  /// Records a direct media URL (from the relay, network capture or probe)
  /// and surfaces the "Play natively" affordance. A stream with a real
  /// position (relay/probe) wins over a position-less network capture.
  void _setNativeStream(String url, Duration position, {String via = 'probe'}) {
    final current = _nativeStream;
    if (current != null && current.position > Duration.zero) return;
    if (current != null && position <= Duration.zero) return;
    if (!mounted) return;
    setState(() {
      _nativeStream = WebViewNativeStream(url: url, position: position);
    });
    // NOTE: the probe timer keeps running (until this screen pops) — the
    // auto-handoff stability tracker needs the continuing probe stream to
    // confirm playback is genuinely advancing.
    debugPrint(
      'FILMKU_WEBVIEW_NATIVE_READY via=$via url=$url '
      'posMs=${position.inMilliseconds}',
    );
  }

  Future<void> _probeNativeStream() async {
    final controller = _controller;
    if (controller == null) return;
    final String raw;
    try {
      raw = (await controller.evaluateJavascript(
            source: WebViewPlayerScreen._probeVideoJs,
          )) ??
          '';
    } catch (_) {
      return; // Page mid-navigation — try again next tick.
    }
    if (raw.isEmpty || raw == 'null') return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      // A blank document (about:blank / empty body) is the white-screen
      // signature of a dead source — pop back after a few probes so the
      // player auto-failovers to the next provider instead of stranding the
      // user on white. Checked BEFORE the URL branch so a blank page with no
      // video (the normal case) is still detected.
      //
      // Blank probes are only counted AFTER the page finished loading
      // (onLoadStop): the pre-navigation about:blank window and a slow
      // player shell that hasn't mounted its body yet would otherwise
      // false-positive and escape away from a working source.
      if (!_loading && WebViewPlayerScreen.isBlankProbe(decoded)) {
        _blankProbes++;
        if (WebViewPlayerScreen.shouldSurfaceBlankError(_blankProbes)) {
          _escapeBlankPage();
          return;
        }
      } else {
        _blankProbes = 0;
      }
      // Reflect JS-side ad-strip progress in the visible chip even when the
      // network interceptor never matches a host on this device.
      final ads = decoded['ads'];
      final jsAds = ads is num ? ads.toInt() : 0;
      if (jsAds > _lastJsAds) {
        _lastJsAds = jsAds;
        if (mounted && jsAds > _adBlocked) {
          setState(() => _adBlocked = jsAds);
        }
      }
      final url = decoded['url'];
      if (url is! String ||
          url.isEmpty ||
          !WebViewPlayerScreen.isNativeStreamCandidate(
            url,
            embedUrl: widget.args.url,
          )) {
        return;
      }
      final seconds = decoded['t'];
      final position = Duration(
        milliseconds: ((seconds is num ? seconds : 0) * 1000).round(),
      );
      _setNativeStream(url, position);
      _trackStability(position);
    } on FormatException {
      // Transient non-JSON eval — try again next tick.
    }
  }

  /// Pops back with NO stream when the loaded document is blank (about:blank
  /// / empty body — a dead or region-blocked source, e.g. 2embed.cc).
  /// [PlayerScreen] then auto-failovers to the next provider in the capped
  /// list instead of showing a white screen. Logged for the on-device trace.
  void _escapeBlankPage() {
    if (_blankEscaped || !mounted) return;
    _blankEscaped = true;
    _probeTimer?.cancel();
    _countdownTimer?.cancel();
    debugPrint(
      'FILMKU_WEBVIEW_BLANK source=${widget.args.sourceLabel} '
      'escape url=${widget.args.url}',
    );
    context.pop();
  }

  /// Pops back to [PlayerScreen] with the discovered native stream so the
  /// playback continues in the ad-free native player at the same position.
  void _handOffToNative() {
    final stream = _nativeStream;
    if (stream == null) return;
    // Resume from the LATEST observed position (the probe keeps running
    // while the countdown ticks) rather than the first capture.
    final position = _lastProbePosition > Duration.zero
        ? _lastProbePosition
        : stream.position;
    context.pop(WebViewNativeStream(url: stream.url, position: position));
  }

  /// Tracks whether playback is genuinely advancing probe-to-probe; starts
  /// the auto-handoff countdown once it has been stable for
  /// [WebViewPlayerScreen.stableProbeThreshold] consecutive probes.
  ///
  /// The freshest observed position is recorded UNCONDITIONALLY (even when
  /// auto-handoff is disabled or the countdown is pending), so both the
  /// auto-handoff and a manual "Play natively" tap resume from where
  /// playback actually is. Only the countdown itself is gated.
  void _trackStability(Duration position) {
    if (position <= Duration.zero) return;
    final previous = _lastProbePosition;
    _lastProbePosition = position;
    if (_handoffPending || !widget.args.autoHandoff || _autoHandoffCancelled) {
      return;
    }
    _stableCount = WebViewPlayerScreen.advanceStableProbe(
      position: position,
      lastPosition: previous,
      count: _stableCount,
    );
    if (_stableCount >= WebViewPlayerScreen.stableProbeThreshold) {
      _startHandoffCountdown();
    }
  }

  /// Shows the countdown chip and pops into the native player when it hits
  /// zero (unless cancelled).
  void _startHandoffCountdown() {
    if (!mounted || _handoffPending) return;
    setState(() {
      _handoffPending = true;
      _countdownLeft = WebViewPlayerScreen.autoHandoffCountdownSeconds;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownLeft <= 1) {
        timer.cancel();
        _handOffToNative();
        return;
      }
      setState(() => _countdownLeft--);
    });
  }

  /// Cancels the pending auto-handoff; the manual button remains available.
  void _cancelAutoHandoff() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (!mounted) return;
    setState(() {
      _handoffPending = false;
      _autoHandoffCancelled = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Intercept the Android system back button: navigate the WebView back
    // first (e.g. escaping an ad page) and only close the player when the
    // WebView has no history to go back to.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          // iOS: swipe down anywhere to leave fullscreen without killing the
          // app from the background. Non-iOS platforms are a pass-through.
          child: PlayerSwipeDismiss(
            onDismiss: () => context.pop(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(widget.args.url)),
                  // Interception (request/fetch/ajax) must be explicitly on for
                  // iOS — defaults are false there, on Android they default on.
                  // Shared builder keeps every capture WebView consistent.
                  initialSettings: buildCaptureWebViewSettings(),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                    _injectAllFramesScript(controller);
                    debugPrint(
                      'FILMKU_WEBVIEW_OPEN source=${widget.args.sourceLabel} '
                      'url=${widget.args.url}',
                    );
                  },
                  // Main-frame navigations to ad landing pages (the "tap
                  // anywhere → ad" hijack) are cancelled before they start.
                  shouldOverrideUrlLoading:
                      (controller, navigationAction) async {
                    final target = navigationAction.request.url;
                    if (target != null &&
                        WebViewPlayerScreen.isAdHost(target.host)) {
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  // Ad/tracker sub-resources are answered with an empty 204 so
                  // their scripts never reach the page. Plain .m3u8/.mp4 media
                  // loads (also from inside iframes) are captured for native
                  // handoff. Everything else loads normally (return null).
                  shouldInterceptRequest: (controller, request) async {
                    final url = request.url.toString();
                    final host = request.url.host;
                    if (WebViewPlayerScreen.isAdHost(host)) {
                      _adBlocked++;
                      debugPrint(
                        'FILMKU_WEBVIEW_ADBLOCK host=$host total=$_adBlocked',
                      );
                      // Throttle UI updates — ad requests can burst.
                      if (mounted && (_adBlocked <= 2 || _adBlocked % 5 == 0)) {
                        setState(() {});
                      }
                      return WebResourceResponse(
                        contentType: 'text/plain',
                        contentEncoding: 'utf-8',
                        statusCode: 204,
                        reasonPhrase: 'Blocked by FilmKU',
                        data: Uint8List(0),
                      );
                    }
                    if (WebViewPlayerScreen.isMediaUrl(url)) {
                      debugPrint('FILMKU_WEBVIEW_CAPTURE url=$url');
                      _setNativeStream(
                        url,
                        Duration.zero,
                        via: 'intercept',
                      );
                    }
                    return null;
                  },
                  // fetch()/XHR media loads (e.g. a JS player fetching the HLS
                  // manifest). NOTE: on Android these JS-injection interceptors
                  // typically reach the top frame only — cross-origin iframe
                  // media (the 2embed case) is caught by the all-frames relay
                  // instead. Returning the request unchanged always continues
                  // it; we only observe.
                  shouldInterceptFetchRequest:
                      (controller, fetchRequest) async {
                    final url = fetchRequest.url.toString();
                    if (WebViewPlayerScreen.isMediaUrl(url)) {
                      debugPrint('FILMKU_WEBVIEW_CAPTURE fetch=$url');
                      _setNativeStream(url, Duration.zero, via: 'fetch');
                    }
                    return fetchRequest;
                  },
                  shouldInterceptAjaxRequest: (controller, ajaxRequest) async {
                    final url = ajaxRequest.url.toString();
                    if (WebViewPlayerScreen.isMediaUrl(url)) {
                      debugPrint('FILMKU_WEBVIEW_CAPTURE ajax=$url');
                      _setNativeStream(url, Duration.zero, via: 'ajax');
                    }
                    return ajaxRequest;
                  },
                  onLoadStop: (controller, url) async {
                    if (mounted) {
                      setState(() {
                        _loading = false;
                        // A main document loaded: a network-level error fired
                        // during the redirect chain is no longer valid — clear
                        // it so the error UI never covers a working player.
                        // HTTP status errors are the real final state and are
                        // kept.
                        if (!_httpError) _error = null;
                      });
                    }
                    // Re-inject the script into the top frame (idempotent): on
                    // devices where the document-start script was too late for
                    // the initial load, this still arms the ad-strip + relay.
                    try {
                      await controller.evaluateJavascript(
                        source: WebViewPlayerScreen._allFramesJs,
                      );
                    } catch (_) {}
                  },
                  // Ad/tracker sub-frame errors fire constantly on these pages.
                  // Surfacing them covers the playing video with a fake error —
                  // only a failure of the original embed document (main frame
                  // at the exact URL we were asked to load) may fail the
                  // player. This also prevents a hijacked ad frame's error from
                  // ever covering the still-playing video.
                  onReceivedError: (controller, request, error) {
                    if (WebViewPlayerScreen.shouldSurfaceLoadError(
                          isForMainFrame: request.isForMainFrame,
                          requestUrl: request.url.toString(),
                          expectedUrl: widget.args.url,
                        ) &&
                        mounted) {
                      setState(() {
                        _loading = false;
                        _httpError = false;
                        _error = 'Failed to load ${widget.args.sourceLabel}. '
                            'Check your connection.';
                      });
                    }
                  },
                  onReceivedHttpError: (controller, request, response) {
                    // Ad/tracker sub-requests often 404/403 — only fail when
                    // the main document itself errors. After a redirect (e.g.
                    // vidsrc.to → vsembed.ru) the URL won't match and the
                    // source's own page (with its error UI) is shown instead.
                    if (WebViewPlayerScreen.shouldSurfaceHttpError(
                          isForMainFrame: request.isForMainFrame,
                          requestUrl: request.url.toString(),
                          expectedUrl: widget.args.url,
                        ) &&
                        mounted) {
                      setState(() {
                        _loading = false;
                        _httpError = true;
                        _error = '${widget.args.sourceLabel} returned '
                            'HTTP ${response.statusCode}.';
                      });
                    }
                  },
                  // Block popup/popunder ad windows — they hijack taps and can't
                  // be dismissed. Returning false prevents window.open from
                  // creating a new window; the player itself runs in this page.
                  onCreateWindow: (controller, createWindowAction) async {
                    return false;
                  },
                ),
                // Back + close — always accessible (immersive mode hides the
                // system back affordances). Back first pops WebView history so
                // the user can escape an ad page and return to the video.
                Positioned(
                  top: 8,
                  left: 8,
                  child: Row(
                    children: [
                      _RoundIconButton(
                        icon: Icons.arrow_back,
                        tooltip: 'Back',
                        onPressed: _goBack,
                      ),
                      const SizedBox(width: 8),
                      _RoundIconButton(
                        icon: Icons.close,
                        tooltip: 'Close player',
                        onPressed: () => context.pop(),
                      ),
                    ],
                  ),
                ),
                // Live proof the ad-block is working.
                if (_adBlocked > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.shield,
                            size: 13,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$_adBlocked iklan diblokir',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_loading)
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.accent),
                        SizedBox(height: 14),
                        Text(
                          'Loading player…',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                if (_error != null)
                  Center(
                    child: ErrorView(
                      message: _error!,
                      onRetry: () => _reload(),
                    ),
                  ),
                // Auto-handoff countdown: playback is stable — switching to
                // the ad-free native player in a few seconds unless cancelled.
                if (_handoffPending)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 48,
                    child: Center(
                      child: Material(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(28),
                        elevation: 6,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.bolt,
                                color: AppColors.accent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Pindah ke player native dalam '
                                '$_countdownLeft s…',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              TextButton(
                                onPressed: _cancelAutoHandoff,
                                child: const Text('Batal'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                // A direct stream URL was found inside the embed player — offer
                // to continue in the ad-free native player at the same spot
                // (hidden while the auto-handoff countdown is running).
                if (_nativeStream != null && !_handoffPending)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 48,
                    child: Center(
                      child: Material(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(28),
                        elevation: 6,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(28),
                          onTap: _handOffToNative,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.black,
                                  size: 22,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Play natively (ad-free)',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Navigates the WebView back one step (escaping ads/redirects); closes the
  /// player when there is no history to go back to.
  Future<void> _goBack() async {
    final controller = _controller;
    if (controller != null) {
      final canGoBack = await controller.canGoBack();
      if (canGoBack) {
        await controller.goBack();
        return;
      }
    }
    if (mounted) context.pop();
  }

  void _reload() {
    setState(() {
      _loading = true;
      _error = null;
      _httpError = false;
    });
    _controller?.reload();
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 22),
        tooltip: tooltip,
      ),
    );
  }
}
