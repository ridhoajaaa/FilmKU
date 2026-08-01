import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/local/settings_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/datasources/stream_source_datasource.dart';
import '../../domain/entities/movie_details.dart';
import '../../domain/entities/video_source.dart';
import '../providers/movie_providers.dart';
import '../widgets/error_view.dart';
import '../widgets/hidden_stream_capture.dart';
import '../widgets/video_player_controls.dart';
import 'mpv_player_screen.dart';
import 'webview_player_screen.dart';

/// Native, ad-free video player. Extracts direct stream links via the
/// SourceAggregator and plays them with `video_player` — no ads render.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.movieId});

  final int movieId;

  /// Picks which source's embed page to open in the WebView fallback:
  /// prefers the source that was actually attempted (it failed natively),
  /// falling back to any source that has an embed page. Exposed for tests.
  @visibleForTesting
  static VideoSource? selectFallbackSource(
    VideoSource? selected,
    List<VideoSource> sources,
  ) {
    if (selected?.embedUrl != null) return selected;
    return sources.where((s) => s.embedUrl != null).firstOrNull;
  }

  /// Builds the ordered list of provider embed pages to try during hidden
  /// auto-capture: every enabled provider that can produce an embed page for
  /// [movieId], in registry order. Auto-capture tries each in turn — when one
  /// times out, the next is tried before falling back to the visible WebView.
  /// Exposed for tests.
  @visibleForTesting
  static List<VideoSource> buildAutoCaptureCandidates(
    int movieId, {
    bool Function(String sourceId)? isSourceEnabled,
  }) {
    final enabled = isSourceEnabled ?? SettingsService.instance.isSourceEnabled;
    final candidates = <VideoSource>[];
    for (final extractor in SourceAggregator.extractors) {
      if (!enabled(extractor.sourceId)) continue;
      final embedUrl = extractor.buildEmbedUrl(movieId);
      if (embedUrl != null) {
        candidates.add(VideoSource(
          sourceId: extractor.sourceId,
          label: extractor.label,
          embedUrl: embedUrl,
        ));
      }
    }
    return candidates;
  }

  /// Builds a last-resort WebView fallback for [movieId] when extraction found
  /// ZERO sources at all (e.g. on-device headless failures): the first enabled
  /// provider's embed page is opened in the in-app WebView, whose real browser
  /// context may still play the stream. Without this, the "Play in WebView"
  /// button is hidden exactly when it is most needed. Exposed for tests.
  @visibleForTesting
  static VideoSource? buildFallbackWebViewSource(
    int movieId, {
    bool Function(String sourceId)? isSourceEnabled,
  }) {
    final candidates =
        buildAutoCaptureCandidates(movieId, isSourceEnabled: isSourceEnabled);
    return candidates.isEmpty ? null : candidates.first;
  }

  /// The next provider index to try after [current] times out, or null when
  /// every candidate has been tried (auto-capture then falls back to the
  /// manual WebView). Exposed for tests.
  @visibleForTesting
  static int? nextAutoCaptureIndex(int current, int length) {
    final next = current + 1;
    return next < length ? next : null;
  }

  /// Maximum number of providers the hidden auto-capture tries before giving
  /// up and auto-opening the visible WebView.
  ///
  /// On-device evidence (2026-08, Redmi Note 8 Pro): the hidden capture
  /// NEVER produced a playable stream on the user's ISP — vidsrc.to's CDN
  /// was refused within ~7s (`ERR_CONNECTION_REFUSED` on its tokenized
  /// hosts) and 2Embed/vidlink never exposed a plain URL to the hidden
  /// WebView, yet the code waited the full 40s+20s×4 = 120s budget per
  /// movie. Capping at 2 bounds the dead wait to ~45s while still giving
  /// the proven visible WebView → mpv auto-handoff a fast shot.
  static const int maxAutoCaptureProviders = 2;

  /// Truncates [candidates] to at most [max] providers, keeping registry
  /// order. Exposed for tests.
  @visibleForTesting
  static List<VideoSource> limitAutoCaptureCandidates(
    List<VideoSource> candidates,
    int max,
  ) {
    if (candidates.length <= max) return candidates;
    return candidates.sublist(0, max);
  }

  /// Builds browser-like headers for a native media request.
  ///
  /// Some CDNs (e.g. VidLink's signed `.mp4`) reject bare ExoPlayer fetches
  /// with HTTP 403/428. Sending a `Referer`/`Origin` matching the source's
  /// embed page plus the app's mobile [AppConstants.defaultUserAgent] mimics
  /// how a real browser would request the stream. Exposed for tests.
  ///
  /// NOTE (experiment 2026-08): a standalone probe showed VidLink's CDN
  /// still answers 428 Precondition Required even with full browser headers
  /// when the TLS fingerprint is not a real browser — so this may not be
  /// enough on its own, but it is the cheapest thing to try on device.
  @visibleForTesting
  static Map<String, String> buildStreamHeaders(VideoSource source) {
    final headers = <String, String>{
      'User-Agent': AppConstants.defaultUserAgent,
      'Accept': '*/*',
    };
    final embedUrl = source.embedUrl;
    if (embedUrl != null && embedUrl.isNotEmpty) {
      final uri = Uri.tryParse(embedUrl);
      // `.origin` throws `Bad state` when the URI has no scheme (e.g. a
      // relative path like `not a url`), so guard before reading it.
      final origin =
          (uri != null && uri.hasScheme && uri.hasAuthority) ? uri.origin : '';
      if (origin.isNotEmpty) {
        headers['Origin'] = origin;
        headers['Referer'] = embedUrl;
      }
    }
    return headers;
  }

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  VideoPlayerController? _controller;
  VideoSource? _selected;
  List<VideoSource> _sources = const <VideoSource>[];
  bool _loading = true;
  String? _error;

  /// True while the hidden capture WebView is hunting for a direct stream URL
  /// (on-device extraction found nothing): the user sees a spinner, then
  /// playback jumps straight into the libmpv native player — no visible
  /// WebView, no ads.
  bool _autoCapturing = false;

  /// Ordered list of provider embed pages to try during hidden auto-capture
  /// (registry order, enabled only). If one times out, the next is tried.
  List<VideoSource> _autoCaptureCandidates = const <VideoSource>[];

  /// Index into [_autoCaptureCandidates] of the provider being tried.
  int _autoCaptureIndex = 0;

  /// The provider whose embed page the hidden capture WebView is loading.
  VideoSource? get _autoCaptureSource {
    if (_autoCaptureIndex >= _autoCaptureCandidates.length) return null;
    return _autoCaptureCandidates[_autoCaptureIndex];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enterLandscape();
      _loadSources();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
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

  Future<void> _loadSources() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sources =
          await ref.read(videoSourcesProvider(widget.movieId).future);
      if (!mounted) return;
      setState(() => _sources = sources);

      final playable = sources.where((s) => s.isPlayable).toList();
      // TEMP-DIAG: on-device extraction yields zero playable streams
      // (OCR-verified screen). Log the extraction outcome — source count,
      // per-source playability and the headless toggle — so logcat shows
      // exactly why. Remove after the investigation concludes.
      debugPrint(
        'FILMKU_EXTRACT_SUMMARY movieId=${widget.movieId} '
        'total=${sources.length} playable=${playable.length} '
        'headlessEnabled=${SettingsService.instance.headlessExtraction}',
      );
      for (var i = 0; i < sources.length; i++) {
        final s = sources[i];
        debugPrint(
          'FILMKU_EXTRACT_SUMMARY i=$i label=${s.label} '
          'sourceId=${s.sourceId} isPlayable=${s.isPlayable} '
          'videoUrl=${s.videoUrl} embedUrl=${s.embedUrl}',
        );
      }
      if (playable.isEmpty) {
        await _beginAutoCapture();
        return;
      }
      await _initPlayer(playable.first);
    } catch (error, stackTrace) {
      // TEMP-DIAG: the provider itself threw (e.g. aggregator error) —
      // distinct from the per-source misses logged upstream.
      debugPrint(
        'FILMKU_EXTRACT_SUMMARY loadError movieId=${widget.movieId} '
        'type=${error.runtimeType} error=$error',
      );
      debugPrint('FILMKU_EXTRACT_SUMMARY stack=$stackTrace');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _initPlayer(VideoSource source) async {
    final old = _controller;
    _controller = null;
    await old?.dispose();

    final url = source.videoUrl;
    if (url == null) {
      setState(() {
        _selected = source;
        _loading = false;
        _error = '${source.label} has no direct stream.';
      });
      return;
    }

    setState(() {
      _selected = source;
      _loading = true;
      _error = null;
    });

    // Experimental: some CDNs (e.g. VidLink) reject bare ExoPlayer requests.
    // When the setting is on, replay the embed page's Origin/Referer + mobile
    // UA on the media request. Probe evidence suggests the CDN may still
    // demand a real browser TLS fingerprint, but this is the cheapest thing
    // to try on device before falling back to the WebView player.    // TEMP-DIAG: capture what was actually sent so the logcat analysis can
    // prove whether headers were on/off during the failed attempt. Remove
    // together with the catch-block logging after the experiment.
    final headersOn = SettingsService.instance.browserHeaders;
    final httpHeaders = headersOn
        ? PlayerScreen.buildStreamHeaders(source)
        : const <String, String>{};
    debugPrint(
      'FILMKU_PLAYER_INIT_REQUEST headersOn=$headersOn '
      'headers=$httpHeaders url=$url',
    );
    final controller = VideoPlayerController.networkUrl(Uri.parse(url),
        httpHeaders: httpHeaders);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();
      if (mounted) setState(() => _loading = false);
    } catch (error, stackTrace) {
      // TEMP-DIAG: log the full error so logcat shows the CDN's actual HTTP
      // response (403/428) inside ExoPlayer's HttpDataSourceException.
      // Remove after the on-device experiment is concluded.
      debugPrint('FILMKU_PLAYER_INIT_ERROR source=${source.label}');
      debugPrint('FILMKU_PLAYER_INIT_ERROR url=$url');
      debugPrint('FILMKU_PLAYER_INIT_ERROR type=${error.runtimeType}');
      debugPrint('FILMKU_PLAYER_INIT_ERROR error=$error');
      debugPrint('FILMKU_PLAYER_INIT_ERROR stack=$stackTrace');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load the stream from ${source.label}. '
              'Try another source.';
        });
      }
    }
  }

  /// Opens the selected source's embed page in the in-app WebView fallback
  /// player — used when auto-capture times out, the user picks it manually,
  /// or the native (mpv) player cannot play the handed-off stream.
  ///
  /// When the embed player exposes a direct stream URL (its `<video>` is
  /// polling plain http(s) media, not MSE `blob:`), the WebView pops with a
  /// [WebViewNativeStream] and playback continues in the libmpv native
  /// player (`/mpv-player`) at the same position. If mpv fails too, we pop
  /// straight back into the WebView so the movie keeps playing — with
  /// [autoHandoff] disabled so the WebView doesn't immediately bounce back
  /// into the failing native player (loop).
  Future<void> _openWebViewFallback(
    VideoSource source, {
    bool autoHandoff = true,
  }) async {
    final embedUrl = source.embedUrl;
    if (embedUrl == null) return;
    final stream = await context.push<WebViewNativeStream>(
      '/webview-player',
      extra: WebViewPlayerArgs(
        url: embedUrl,
        sourceLabel: source.label,
        autoHandoff: autoHandoff,
      ),
    );
    if (!mounted || stream == null) {
      // The WebView popped without a handoff — either the user closed it or
      // the source served a BLANK page (about:blank → white screen, detected
      // by the WebView). Auto-failover to the next provider in the capped
      // list instead of landing on the error screen; only when every
      // provider has been tried do we surface the error view.
      final next = PlayerScreen.nextAutoCaptureIndex(
        _autoCaptureIndex,
        _autoCaptureCandidates.length,
      );
      if (next != null) {
        final nextSource = _autoCaptureCandidates[next];
        if (nextSource.embedUrl != null) {
          debugPrint(
            'FILMKU_WEBVIEW_BLANK_FAILOVER '
            '${_autoCaptureCandidates[_autoCaptureIndex].sourceId} -> '
            '${nextSource.sourceId}',
          );
          setState(() => _autoCaptureIndex = next);
          _openWebViewFallback(nextSource);
          return;
        }
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'No playable stream found for this movie.\n'
              'Try again or enable more sources in Settings.';
        });
      }
      return;
    }
    debugPrint(
      'FILMKU_WEBVIEW_HANDOFF source=${source.sourceId} '
      'url=${stream.url} position=${stream.position}',
    );
    await _playInMpv(stream, source);
  }

  /// Plays a handed-off/auto-captured direct stream in the libmpv native
  /// player. Pops the whole player on a normal close; on failure returns to
  /// the visible WebView so the movie keeps playing.
  Future<void> _playInMpv(
      WebViewNativeStream stream, VideoSource source) async {
    final failed = await context.push<bool>(
      '/mpv-player',
      extra: MpvPlayerArgs(
        url: stream.url,
        title: _movieTitle(),
        sourceLabel: source.label,
        startAt: stream.position,
      ),
    );
    if (!mounted) return;
    if (failed == true) {
      // Native playback failed — return to the WebView seamlessly, with
      // auto-handoff DISABLED so the WebView doesn't immediately bounce
      // back into the failing native player (loop).
      debugPrint(
        'FILMKU_MPV_FAILED_RETURN_WEBVIEW source=${source.sourceId} '
        'autoHandoff=false',
      );
      await _openWebViewFallback(source, autoHandoff: false);
    } else {
      // The user finished/closed the native playback — leave the player
      // instead of lingering on the stale "no playable stream" error screen.
      debugPrint(
        'FILMKU_MPV_CLOSED_NORMAL source=${source.sourceId}',
      );
      context.pop();
    }
  }

  /// Starts hidden auto-capture: when on-device extraction finds nothing, load
  /// the first enabled provider's embed page in an INVISIBLE WebView, capture
  /// the direct stream URL its player requests, and jump straight into the
  /// native (libmpv) player — the user never sees a WebView or its ads.
  Future<void> _beginAutoCapture() async {
    var candidates = PlayerScreen.buildAutoCaptureCandidates(widget.movieId);
    if (candidates.isEmpty) {
      final fromExtraction =
          PlayerScreen.selectFallbackSource(_selected, _sources);
      if (fromExtraction != null) candidates = [fromExtraction];
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No playable stream found for this movie.\n'
            'Try again or enable more sources in Settings.';
      });
      return;
    }
    // On-device evidence (2026-08): the hidden capture has never produced a
    // playable URL on the user's ISP — every provider times out. Capping at
    // [PlayerScreen.maxAutoCaptureProviders] cuts the dead wait from ~120s
    // to ~45s and hands the proven visible WebView → mpv auto-handoff a fast
    // shot instead of burning budget on all 5 providers.
    if (candidates.length > PlayerScreen.maxAutoCaptureProviders) {
      debugPrint(
        'FILMKU_AUTOCAPTURE_TRUNCATE '
        'from=${candidates.length} to=${PlayerScreen.maxAutoCaptureProviders} '
        'kept=${candidates.take(PlayerScreen.maxAutoCaptureProviders).map((c) => c.sourceId).join(',')}',
      );
      candidates = PlayerScreen.limitAutoCaptureCandidates(
        candidates,
        PlayerScreen.maxAutoCaptureProviders,
      );
    }
    debugPrint(
      'FILMKU_AUTOCAPTURE_BEGIN candidates='
      '${candidates.map((c) => c.sourceId).join(',')}',
    );
    setState(() {
      _loading = false;
      _autoCapturing = true;
      _autoCaptureCandidates = candidates;
      _autoCaptureIndex = 0;
    });
  }

  void _onAutoCaptured(WebViewNativeStream stream) {
    final source = _autoCaptureSource;
    if (!mounted) return;
    debugPrint(
      'FILMKU_AUTOCAPTURE_OK source=${source?.sourceId} '
      'url=${stream.url} posMs=${stream.position.inMilliseconds}',
    );
    setState(() {
      _autoCapturing = false;
      _autoCaptureCandidates = const <VideoSource>[];
      _autoCaptureIndex = 0;
    });
    if (source != null) _playInMpv(stream, source);
  }

  void _onAutoCaptureTimeout() {
    if (!mounted || !_autoCapturing) return;
    final next = PlayerScreen.nextAutoCaptureIndex(
        _autoCaptureIndex, _autoCaptureCandidates.length);
    if (next != null) {
      debugPrint(
        'FILMKU_AUTOCAPTURE_TIMEOUT retry '
        '${_autoCaptureCandidates[_autoCaptureIndex].sourceId} -> '
        '${_autoCaptureCandidates[next].sourceId}',
      );
      setState(() => _autoCaptureIndex = next);
      return;
    }
    debugPrint('FILMKU_AUTOCAPTURE_TIMEOUT all providers exhausted');
    // Auto-open the visible WebView for the BEST-ranked provider (registry
    // order = reliability order, so the FIRST candidate is the one most
    // likely to actually play on-device — e.g. VidLink, which is proven).
    // Hidden-capture failure does NOT predict visible-WebView failure: the
    // hidden capture never succeeds on this ISP, yet the visible WebView →
    // mpv auto-handoff does. Opening the LAST-tried provider would surface a
    // dead/blank source (e.g. 2embed.cc → about:blank white screen).
    //
    // The candidates list is KEPT (index reset to 0) so that if this WebView
    // pops without a stream (blank page / closed), _openWebViewFallback can
    // auto-failover to the next provider instead of the error screen.
    final bestSource =
        _autoCaptureCandidates.isEmpty ? null : _autoCaptureCandidates.first;
    setState(() {
      _autoCapturing = false;
      _autoCaptureIndex = 0;
    });
    if (bestSource?.embedUrl != null) {
      _openWebViewFallback(bestSource!);
    } else {
      setState(() {
        _autoCapturing = false;
        _autoCaptureCandidates = const <VideoSource>[];
        _autoCaptureIndex = 0;
        _loading = false;
        _error = 'No playable stream found for this movie.\n'
            'Try again or enable more sources in Settings.';
      });
    }
  }

  void _cancelAutoCaptureAndOpenWebView() {
    final source = _autoCaptureSource;
    if (!mounted) return;
    setState(() => _autoCapturing = false);
    if (source != null) _openWebViewFallback(source);
  }

  String _movieTitle() {
    final details = ref.read(movieDetailsProvider(widget.movieId));
    return _movieTitleFrom(details);
  }

  void _pickSource() async {
    final picked = await showModalBottomSheet<VideoSource>(
      context: context,
      backgroundColor: AppColors.charcoal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Source',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final source in _sources)
                    ListTile(
                      leading: Icon(
                        source.isPlayable
                            ? Icons.play_circle_fill
                            : Icons.error_outline,
                        color: source.isPlayable
                            ? AppColors.accent
                            : AppColors.textMuted,
                      ),
                      title: Text(
                        source.label,
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                      subtitle: Text(
                        '${source.quality} • ${source.sourceId}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      trailing: source.sourceId == _selected?.sourceId
                          ? const Icon(Icons.check_circle,
                              color: AppColors.accent)
                          : null,
                      onTap: source.isPlayable
                          ? () => Navigator.pop(context, source)
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      await _initPlayer(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched unconditionally at the top of build — Riverpod requires the
    // set of watched providers to stay stable across rebuilds.
    final details = ref.watch(movieDetailsProvider(widget.movieId));
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _buildBody(title: _movieTitleFrom(details)),
      ),
    );
  }

  Widget _buildBody({required String title}) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Finding stream sources…',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    if (_autoCapturing) {
      final source = _autoCaptureSource;
      final embedUrl = source?.embedUrl;
      final total = _autoCaptureCandidates.length;
      final current = _autoCaptureIndex + 1;
      return Stack(
        fit: StackFit.expand,
        children: [
          // FULL-SIZE, genuinely-visible capture WebView (see HiddenStreamCapture
          // doc: on-device diagnosis proved the embed player only starts when
          // the WebView is a real visible Android view — Opacity(0) and
          // off-screen both fail to make it request the m3u8). The opaque
          // overlay below is painted ON TOP, so the user still sees only the
          // spinner — but the WebView itself behaves exactly like the
          // proven-working manual WebView. Keyed by provider so a timeout →
          // next-provider switch creates a FRESH WebView + timers.
          if (source != null && embedUrl != null)
            HiddenStreamCapture(
              key: ValueKey('${source.sourceId}-$_autoCaptureIndex'),
              url: embedUrl,
              sourceLabel: source.label,
              onCaptured: _onAutoCaptured,
              onTimeout: _onAutoCaptureTimeout,
              // On-device evidence (2026-08): the source's player takes ~26s
              // to request its m3u8 even when working (manual capture at
              // 25.8s), but on the user's ISP every provider times out — the
              // CDNs are refused within ~7s yet the old 40s budget burned
              // the full 120s across 5 providers. First provider gets 30s
              // (safely above the observed 25.8s successful capture, so
              // working networks aren't starved); the second gets 20s (the
              // LAST hidden-capture chance before the visible WebView takes
              // over — a dead source only needs a small budget to be
              // abandoned).
              timeout: _autoCaptureIndex == 0
                  ? const Duration(seconds: 30)
                  : const Duration(seconds: 20),
            ),
          // Opaque overlay: hides the capture WebView (and any transient ads)
          // behind a solid surface while showing the hunt progress. Opaque
          // PAINT does not change the platform view's visibility, so the
          // player keeps running underneath.
          Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.accent),
                  const SizedBox(height: 16),
                  const Text(
                    'Mencari stream tanpa iklan…',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  if (total > 1)
                    Text(
                      'Sumber $current/$total — ${source?.label ?? ''}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (embedUrl != null)
                    TextButton(
                      onPressed: _cancelAutoCaptureAndOpenWebView,
                      child: const Text('Buka di WebView (manual)'),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (_error != null) {
      // When extraction found nothing at all (the common on-device case),
      // still offer the WebView fallback using the first enabled provider's
      // embed page — otherwise the escape hatch is hidden exactly when the
      // user needs it most.
      final fallbackSource =
          PlayerScreen.selectFallbackSource(_selected, _sources) ??
              PlayerScreen.buildFallbackWebViewSource(widget.movieId);
      return ErrorView(
        message: _error!,
        onRetry: _loadSources,
        secondaryLabel: fallbackSource == null ? null : 'Play in WebView',
        onSecondary: fallbackSource == null
            ? null
            : () => _openWebViewFallback(fallbackSource),
        secondaryHint: fallbackSource == null ? null : 'May show source ads',
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const Center(
        child: Text(
          'Player not initialized',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        if (controller.value.isInitialized)
          CustomVideoControls(
            controller: controller,
            title: title,
            sourceLabel: _selected?.label,
            onClose: () => context.pop(),
            onSelectSource: _sources.length > 1 ? _pickSource : null,
          ),
      ],
    );
  }

  static String _movieTitleFrom(AsyncValue<MovieDetails> details) {
    if (details is AsyncData) {
      final title = details.value?.movie.title;
      if (title != null && title.isNotEmpty) return title;
    }
    return 'Now Playing';
  }
}
