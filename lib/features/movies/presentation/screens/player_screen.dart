import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/local/settings_service.dart';
import '../../../../core/local/watch_progress_service.dart';
import '../../../../core/net/hls_relay.dart';
import '../../../../core/platform/orientation_changer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/datasources/stream_source_datasource.dart';
import '../../domain/entities/movie_details.dart';
import '../../domain/entities/video_source.dart';
import '../providers/movie_providers.dart';
import '../providers/watch_history_provider.dart';
import '../widgets/error_view.dart';
import '../widgets/hidden_stream_capture.dart';
import '../widgets/stream_capture_core.dart';
import 'mpv_player_screen.dart';

/// Native, ad-free video player. Extracts direct stream links via the
/// SourceAggregator and plays them with the libmpv native player
/// (`media_kit`) — no ads render.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.movieId, this.resume = false});

  final int movieId;

  /// True when this play was started from the Home "Lanjutkan menonton" row —
  /// the player MUST resume from the saved continue-watching position on
  /// EVERY path (direct extraction AND hidden auto-capture), instead of only
  /// when the stream happens to carry a position (2026-08: replaying from
  /// Home always restarted at 0 because the visible WebView fallback started
  /// fresh — the fallback is gone, so the flag is the single resume gate).
  final bool resume;

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

  /// Revives session-scoped HLS relay URLs in a cached extraction result.
  ///
  /// [videoSourcesProvider] caches its result for the whole app session, but
  /// a relay URL (`http://127.0.0.1:{port}/master.m3u8?src=…`) embeds a
  /// loopback port that dies when the previous playback session ended
  /// ([MiniPlayerService] disposes the relay on stop). Replaying the same
  /// movie would hand mpv a dead URL → "No playable stream found" until a
  /// force-quit clears the provider cache (2026-08 on-device report: closing
  /// a movie with X then replaying it always failed).
  ///
  /// A cached relay URL is STALE (must be re-served) when the relay is dead
  /// ([HlsRelay.port] null) OR bound by a different session (port differs).
  /// A URL whose port matches the live relay (the current session, e.g. the
  /// movie is still minimized) is kept as-is — this also makes the first
  /// play free: extraction already served the URL moments ago, so re-serving
  /// would be a redundant master fetch. A stale URL whose original CDN URL
  /// can no longer be fetched is DROPPED so the flow falls through to
  /// auto-capture (which resolves a fresh URL). Exposed for tests.
  @visibleForTesting
  static Future<List<VideoSource>> reviveRelaySources(
    List<VideoSource> sources, {
    Future<String?> Function(String originalUrl)? serve,
    bool Function(String relayUrl)? isStale,
  }) async {
    final serveRelay = serve ?? (u) => HlsRelay.instance.serve(u);
    final stale = isStale ??
        (url) {
          final currentPort = HlsRelay.instance.port;
          if (currentPort == null) return true; // relay disposed → dead URL
          final uri = Uri.tryParse(url);
          // Different session's relay (different port) → URL is dead too.
          return uri == null || uri.port != currentPort;
        };
    final live = <VideoSource>[];
    for (final source in sources) {
      final url = source.videoUrl;
      String? revived;
      if (url != null && StreamSourceDataSource.isRelayUrl(url)) {
        final original = StreamSourceDataSource.relaySourceOf(url);
        if (original != null && stale(url)) {
          revived = await serveRelay(original);
          if (revived == null) continue; // stale + unresolvable → drop
        }
      }
      live.add(revived == null ? source : source.copyWith(videoUrl: revived));
    }
    return live;
  }

  /// Resolves where a stream handed to the mpv player should start.
  ///
  /// When [resumeRequested] (the play came from the Home "Lanjutkan
  /// menonton" row) the saved continue-watching [savedPosition] is
  /// AUTHORITATIVE: the hidden auto-capture WebView reports a small NON-zero
  /// capture position (it already played 0–30s of the movie while hunting
  /// for the stream URL — 2026-08 probe `t:26.4`), and letting that tiny
  /// position win over e.g. a 34-minute saved position reset the resume
  /// point to the first seconds (the "Lanjutkan menonton still starts from
  /// the beginning" bug). The capture position is only a resume hint when
  /// there is NO saved progress.
  ///
  /// Without [resumeRequested] (a fresh play from Detail) the stream's own
  /// position wins when non-zero (a genuine WebView hand-off stream keeps
  /// its position), and a saved position is only a fallback for zero-position
  /// streams. Exposed for tests.
  @visibleForTesting
  static Duration resolveStartPosition({
    required Duration streamPosition,
    required Duration? savedPosition,
    bool resumeRequested = false,
  }) {
    if (resumeRequested && (savedPosition ?? Duration.zero) > Duration.zero) {
      return savedPosition!;
    }
    return streamPosition > Duration.zero
        ? streamPosition
        : (savedPosition ?? Duration.zero);
  }

  /// Builds the HTTP headers mpv should send to the stream CDN.
  ///
  /// 2026-08 iOS root cause: the signed 2embed/vidlink CDN URLs reject
  /// header-less requests (403), so mpv's `Media(url)` never started on iOS
  /// and the screen failed with "Native playback failed". Passing the embed
  /// page as `Referer` (+ `Origin` + the app's mobile User-Agent, mirroring
  /// what the in-app WebView sends) makes the CDN accept the stream on both
  /// platforms. Exposed for tests.
  @visibleForTesting
  static Map<String, String> buildStreamHeaders(String? embedUrl) {
    final headers = <String, String>{
      'User-Agent': AppConstants.defaultUserAgent,
    };
    if (embedUrl != null && embedUrl.isNotEmpty) {
      headers['Referer'] = embedUrl;
      final uri = Uri.tryParse(embedUrl);
      if (uri != null && uri.hasAuthority && uri.scheme.isNotEmpty) {
        headers['Origin'] = '${uri.scheme}://${uri.authority}';
      }
    }
    return headers;
  }

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
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
    _restorePortrait();
    super.dispose();
  }

  Future<void> _enterLandscape() async {
    // Explicit native landscape first (see OrientationChanger): MIUI ignores
    // Flutter's sensor-based orientation request when auto-rotate is off,
    // leaving the player portrait (video small in the middle, bottom bar
    // mid-screen). setRequestedOrientation(LANDSCAPE) is honored regardless.
    await OrientationChanger.forceLandscape();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _restorePortrait() async {
    await OrientationChanger.restore();
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
      // Re-serve cached relay URLs: the provider result is cached for the
      // whole session, but a relay URL's loopback port dies with the previous
      // playback session — replaying without this hits a dead port (see
      // [reviveRelaySources]).
      final revived = await PlayerScreen.reviveRelaySources(sources);
      if (!mounted) return;

      final playable = revived.where((s) => s.isPlayable).toList();
      // TEMP-DIAG: on-device extraction yields zero playable streams
      // (OCR-verified screen). Log the extraction outcome — source count,
      // per-source playability and the headless toggle — so logcat shows
      // exactly why. Remove after the investigation concludes.
      debugPrint(
        'FILMKU_EXTRACT_SUMMARY movieId=${widget.movieId} '
        'total=${revived.length} playable=${playable.length} '
        'headlessEnabled=${SettingsService.instance.headlessExtraction}',
      );
      for (var i = 0; i < revived.length; i++) {
        final s = revived[i];
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

  /// Plays a direct extraction URL in the libmpv native player (media_kit).
  ///
  /// Direct URLs are ALWAYS played with mpv — `video_player` (ExoPlayer on
  /// Android, AVPlayer on iOS) has repeatedly failed on-device for these CDN
  /// streams (403/428 on signed URLs, MediaCodec renderer crashes), while mpv
  /// is the ONE native player proven on both platforms. On iOS the extraction
  /// usually SUCCEEDS (unlike Android), so the old `_initPlayer` would try
  /// AVPlayer, fail, and dump the user into "Play in WebView" — routing here
  /// makes iOS identical to Android: extraction → native mpv, no detour. On
  /// mpv failure the caller returns to the WebView fallback.
  Future<void> _initPlayer(VideoSource source) async {
    final url = source.videoUrl;
    if (url == null) {
      setState(() {
        _loading = false;
        _error = '${source.label} has no direct stream.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    debugPrint('FILMKU_PLAYER_DIRECT source=${source.sourceId} url=$url');
    await _playInMpv(
      // Position resolved centrally in [_playInMpv] (stream position wins,
      // saved continue-watching position is the fallback) so EVERY entry
      // path — direct extraction, hidden auto-capture — resumes identically.
      WebViewNativeStream(url: url, position: Duration.zero),
      source,
    );
  }

  /// Plays a direct extraction / auto-captured stream in the libmpv native
  /// player. Pops the whole player on a normal close; on a FAILED playback
  /// (the stream never started / stalled) shows the error UI with Retry —
  /// there is NO visible WebView fallback anymore (2026-08: the WebView
  /// sometimes took over a movie that was already playing fine in mpv, and
  /// it always restarted a resumed movie from 0).
  Future<void> _playInMpv(
      WebViewNativeStream stream, VideoSource source) async {
    // Continue-watching resume: the stream's own position wins (a stream
    // that already carried a real position keeps it); otherwise the SAVED
    // position resumes the movie where the user left off — but only when
    // this play was requested FROM the continue-watching row ([resume]); a
    // fresh play from the Detail screen starts from the beginning.
    final saved = widget.resume
        ? WatchProgressService.instance.get(widget.movieId)?.position
        : null;
    final startAt = PlayerScreen.resolveStartPosition(
      streamPosition: stream.position,
      savedPosition: saved,
      // The hidden auto-capture WebView reports a small NON-zero capture
      // position (it played 0–30s while capturing the stream URL). For a
      // resume play that tiny position must NOT override the saved
      // continue-watching position (2026-08: resuming jumped back to the
      // first seconds) — the saved position is authoritative here.
      resumeRequested: widget.resume,
    );
    debugPrint(
      'FILMKU_PLAYER_RESUME_LOOKUP movieId=${widget.movieId} '
      'resumeRequested=${widget.resume} '
      'saved=${saved?.inMilliseconds ?? -1}ms '
      'streamPos=${stream.position.inMilliseconds}ms '
      '-> startAt=${startAt.inMilliseconds}ms source=${source.sourceId}',
    );
    final failed = await context.push<bool>(
      '/mpv-player',
      extra: MpvPlayerArgs(
        url: stream.url,
        title: _movieTitle(),
        sourceLabel: source.label,
        startAt: startAt,
        // WebView-handoff streams may carry the browser session (Cookie)
        // headers captured from the WebView — merged over the standard
        // Referer/Origin/UA so cookie-gated CDNs accept the handed-off URL.
        // Source-level headers (e.g. the exact Referer a provider API like
        // VidNest returns for its streams) override the derived ones.
        httpHeaders: {
          ...PlayerScreen.buildStreamHeaders(source.embedUrl),
          ...source.httpHeaders,
          ...stream.httpHeaders,
        },
        // Enables EXTERNAL subtitles (Indonesian-first) when the stream has
        // no subtitle tracks of its own — title + year make SubtitleCat work
        // WITHOUT a TMDB API key (2026-08: keyless iOS builds showed no
        // subtitles because the old path needed TMDB for every lookup).
        tmdbId: widget.movieId,
        movieYear: _movieYear(),
        // Poster for the continue-watching entry (Home "Lanjutkan menonton").
        posterPath: _moviePosterPath(),
      ),
    );
    if (!mounted) return;
    // The mpv screen records the play in the full watch history on its first
    // real frame — refresh the provider so the Home "Riwayat tontonan" count
    // and the HistoryScreen list update right away (2026-08: without this the
    // provider snapshot stayed stale until an app restart).
    ref.read(watchHistoryProvider.notifier).refresh();
    if (failed == true) {
      // Native playback failed — no WebView fallback anymore (2026-08).
      // Surface the error with Retry; a retry re-runs extraction and may
      // resolve a fresher URL for this movie.
      debugPrint(
        'FILMKU_MPV_FAILED_ERROR_UI source=${source.sourceId}',
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _autoCapturing = false;
          _autoCaptureCandidates = const <VideoSource>[];
          _autoCaptureIndex = 0;
          _error = 'Native playback failed for ${source.label}.\n'
              'Try again or enable more sources in Settings.';
        });
      }
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
    // No visible WebView fallback anymore (2026-08): surface the error with
    // Retry, which re-runs extraction + auto-capture.
    if (mounted) {
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

  String _movieTitle() {
    final details = ref.read(movieDetailsProvider(widget.movieId));
    return _movieTitleFrom(details);
  }

  /// Poster path of the movie (from its TMDB details) — stored with the
  /// watch-progress entry so the Home "Lanjutkan menonton" row can render it.
  String? _moviePosterPath() {
    final details = ref.read(movieDetailsProvider(widget.movieId));
    if (details is AsyncData) {
      return details.value?.movie.posterPath;
    }
    return null;
  }

  /// Release year of the movie (from its TMDB release date) — passed to the
  /// mpv player so EXTERNAL subtitles can use SubtitleCat's title+year
  /// search without any TMDB API call.
  String? _movieYear() {
    final details = ref.read(movieDetailsProvider(widget.movieId));
    if (details is AsyncData) {
      final date = details.value?.movie.releaseDate;
      if (date != null && date.length >= 4) return date.substring(0, 4);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Watched unconditionally at the top of build — Riverpod requires the
    // set of watched providers to stay stable across rebuilds (the title is
    // read lazily in [_movieTitle] when the mpv player is pushed).
    ref.watch(movieDetailsProvider(widget.movieId));
    return Scaffold(
      backgroundColor: Colors.black,
      // See MpvPlayerScreen: MIUI reports phantom bottom viewInsets that
      // Scaffold's default resize would translate into a compressed body
      // ("controls in the middle"). Keep the loading/error body full-screen.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
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
                ],
              ),
            ),
          ),
        ],
      );
    }
    // Error state — or the transient gap between mpv closing and the pop
    // (direct URLs route straight to the mpv player, so this screen only
    // shows loading / auto-capture / error). No WebView fallback anymore
    // (2026-08): Retry re-runs extraction + hidden auto-capture.
    return ErrorView(
      message: _error ??
          'No playable stream found for this movie.\n'
              'Try again or enable more sources in Settings.',
      onRetry: _loadSources,
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
