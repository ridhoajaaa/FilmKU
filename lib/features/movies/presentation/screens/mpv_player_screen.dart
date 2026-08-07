import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/local/watch_history_service.dart';
import '../../../../core/local/watch_progress_service.dart';
import '../../../../core/media/mini_player_service.dart';
import '../../../../core/platform/orientation_changer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/datasources/subtitle_datasource.dart';
import '../providers/movie_providers.dart';
import '../widgets/error_view.dart';
import '../widgets/mpv_controls_overlay.dart';
import '../widgets/player_swipe_dismiss.dart';

/// Arguments for the mpv native player route (WebView handoff streams).
class MpvPlayerArgs {
  const MpvPlayerArgs({
    required this.url,
    required this.title,
    required this.sourceLabel,
    this.startAt = Duration.zero,
    this.httpHeaders = const <String, String>{},
    this.tmdbId,
    this.movieYear,
    this.imdbId,
    this.posterPath,
  });

  /// Direct `.m3u8`/`.mp4` URL captured from inside the WebView fallback.
  final String url;

  /// Movie title shown in the top bar.
  final String title;

  /// Human-readable provider name.
  final String sourceLabel;

  /// Where the stream should resume from (continue-watching position).
  final Duration startAt;

  /// TMDB id of the movie — used to fetch EXTERNAL subtitles (YIFY,
  /// keyless) when the stream itself has no subtitle tracks (the common
  /// case: 2vcdn playlists carry zero `#EXT-X-MEDIA` lines).
  final int? tmdbId;

  /// Release year of the movie — lets the EXTERNAL subtitle fetch use
  /// SubtitleCat's title+year search WITHOUT a TMDB API key (2026-08: iOS
  /// builds without a key silently showed "no subtitles" because the old
  /// path needed TMDB for every lookup).
  final String? movieYear;

  /// IMDB id (when already known) — lets the YIFY subtitle chain run
  /// without a TMDB `external_ids` lookup.
  final String? imdbId;

  /// Poster path of the movie — stored with the watch-progress entry so the
  /// Home "Lanjutkan menonton" row can render the poster.
  final String? posterPath;

  /// Extra HTTP headers sent on every request to the stream CDN (mpv's
  /// `http-header-fields`).
  ///
  /// 2026-08 iOS root cause: the signed 2embed/vidlink CDN URLs return 403
  /// to a header-less request — mpv opened `Media(url)` with NO headers, so
  /// on iOS (where the extraction/CDN chain differs from Android) playback
  /// never started and the screen failed with "Native playback failed".
  /// Passing the embed page as `Referer` (+ `Origin` + the app User-Agent)
  /// makes the CDN accept the stream on BOTH platforms.
  final Map<String, String> httpHeaders;
}

/// Native player backed by libmpv (`media_kit`).
///
/// ExoPlayer's MediaCodec renderer crashes on some HLS MPEG-TS streams on
/// certain devices (observed on-device: `MediaCodecVideoRenderer error ...`
/// on a Xiaomi while the same stream plays fine in a WebView). libmpv
/// transparently falls back to software decoding, so this screen is the
/// native destination for streams handed off from the WebView fallback.
///
/// Pops with `true` when playback failed (the caller should return to the
/// WebView fallback), `false`/null on a normal close.
class MpvPlayerScreen extends StatefulWidget {
  const MpvPlayerScreen({super.key, required this.args});

  final MpvPlayerArgs args;

  /// Whether a media-kit error should surface as the full-screen failure UI.
  ///
  /// mpv emits transient errors (a dropped segment, a failed subtitle/extra
  /// lookup) even while the video is playing fine — surfacing them covered a
  /// still-playing movie with a fake "Native playback failed …" overlay
  /// (observed on iOS, 2026-08: the error UI rendered on top while the video
  /// kept playing behind it). The failure UI is only shown when there is NO
  /// evidence of real playback at all — neither a playing=true event nor an
  /// advanced position (a successful seek also proves the stream loads).
  /// Exposed for tests.
  @visibleForTesting
  static bool shouldSurfaceFailure({
    required bool sawPlaying,
    required Duration lastPosition,
  }) =>
      !sawPlaying && lastPosition <= Duration.zero;

  /// Whether the periodic silent-freeze watchdog should surface a failure.
  ///
  /// Catches a stream that dies WITHOUT emitting any error event (e.g. the
  /// CDN silently kills the connection mid-playback): playback state is still
  /// `playing` but the RAW position has not changed since the last watchdog
  /// tick.
  ///
  /// The comparison is STRICT EQUALITY on the raw position, not `<=`:
  /// `currentPosition` is the raw current playback position which moves
  /// BACKWARD on a user seek — a `<` result (30s vs the pre-seek 120s) proves
  /// the stream responded, so it must NOT be flagged as a stall. Only an
  /// exactly-unchanged position between two ticks (a real freeze) surfaces.
  /// (The monotonic high-watermark [_lastPosition] is NOT used here — it
  /// never decreases, so it would falsely stall after every rewind.)
  /// Exposed for tests.
  @visibleForTesting
  static bool shouldSurfaceSilentFreeze({
    required bool playing,
    required bool sawPlaying,
    required Duration currentPosition,
    required Duration lastWatchPosition,
  }) =>
      playing && sawPlaying && currentPosition == lastWatchPosition;

  /// Whether a mid-play error that produced NO progress at all should be
  /// treated as a never-started stream (compact auto-failover to the backup
  /// player) instead of a genuine mid-playback stall (full error UI with
  /// Retry).
  ///
  /// 2026-08 root cause: libmpv reports `playing` while the stream is STILL
  /// LOADING (the core is not idle while it fetches the master playlist), so
  /// an error arriving while the position is still zero means the CDN
  /// rejected the stream before the first frame (vidlink's signed URLs →
  /// HTTP 403/428 with an unfillable `headers={}` template). That must NOT
  /// park the full "Native playback failed" UI over a still-loading player.
  /// Once the position advanced past zero, real playback happened, so a
  /// subsequent stall keeps the full error UI.
  /// Exposed for tests.
  @visibleForTesting
  static bool shouldAutoFailoverOnStall({required Duration lastPosition}) =>
      lastPosition <= Duration.zero;

  /// How long the "switching to backup player…" notice stays up before the
  /// screen auto-pops with `failed=true` (so [PlayerScreen] continues in the
  /// visible WebView fallback — which is proven to actually play these CDN
  /// streams — instead of parking on a dead-end error UI over a loading
  /// player). Long enough to read the real CDN error shown in the notice
  /// (e.g. "HTTP 428"), short enough to not feel like another dead-end wait.
  /// Exposed for tests.
  @visibleForTesting
  static const Duration failoverNoticeDuration = Duration(milliseconds: 2500);

  @override
  State<MpvPlayerScreen> createState() => _MpvPlayerScreenState();
}

class _MpvPlayerScreenState extends State<MpvPlayerScreen> {
  /// The native player + view controller are owned by [MiniPlayerService]
  /// (so the mini player keeps the session alive after this route pops).
  /// Assigned asynchronously in [_initPlayer].
  late Player _player;
  VideoController? _videoController;
  bool _failed = false;

  /// True when [_failed] came from a stream that NEVER started (startup
  /// timeout / open error) and the screen is auto-failing-over to the backup
  /// player: build shows a brief "switching…" notice (with Retry suppressed —
  /// retrying the same dead URL is pointless) instead of the full error UI,
  /// then pops with `failed=true`. Mid-play failures (silent freeze, error
  /// stall) keep the full error UI with Retry.
  bool _autoFailover = false;

  /// The real reason a never-started stream failed (e.g. the CDN's HTTP 403/
  /// 428 from a signed vidlink URL), shown under the "switching…" notice so
  /// the user sees WHY before the screen auto-pops into the WebView.
  String _failoverDetail = '';
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Tracks>? _tracksSub;

  /// True once playback has actually started (playing=true). Transient errors
  /// after this are ignored — the video is demonstrably playing behind the
  /// error UI.
  bool _sawPlaying = false;

  /// Latest observed playback position (confirms real progress).
  Duration _lastPosition = Duration.zero;

  /// Fails the screen if the stream never starts within this window (bad URL,
  /// blocked CDN) instead of leaving a black screen forever.
  static const Duration _startupTimeout = Duration(seconds: 12);
  Timer? _startupWatchdog;

  Timer? _failoverTimer;

  /// When an error arrives WHILE playback is progressing, this grace window
  /// distinguishes a transient hiccup (position keeps advancing → ignore)
  /// from a genuine mid-playback stall (no progress → surface the failure so
  /// the user can retry / go back to the WebView instead of a frozen frame).
  static const Duration _errorGracePeriod = Duration(seconds: 4);
  Timer? _errorGraceTimer;

  /// Silent-freeze watchdog period: while playback is supposedly running, if
  /// the RAW position doesn't advance within this window the stream has
  /// silently died (no error event — e.g. the CDN kills the connection).
  /// Surfaces the failure so the user can retry / go back to the WebView
  /// instead of staring at a frozen frame forever.
  static const Duration _silentFreezePeriod = Duration(seconds: 20);
  Timer? _silentFreezeWatchdog;

  /// RAW current position (updates on EVERY position event, even backward
  /// seeks) — what the silent-freeze watchdog compares across ticks.
  Duration _currentPosition = Duration.zero;

  /// Raw position at the last watchdog tick (see [shouldSurfaceSilentFreeze]).
  Duration _lastWatchPosition = Duration.zero;

  /// How many consecutive watchdog ticks showed no position change. A single
  /// frozen tick can be a slow-network rebuffer (mpv keeps `playing` true
  /// while rebuffering); only TWO consecutive frozen ticks ([_silentFreezePeriod]
  /// × 2 = 40s of zero movement) surface the failure.
  int _silentFreezeConsecutive = 0;

  /// One-shot per open: whether the first subtitle track was auto-selected.
  /// libmpv only auto-enables DEFAULT/forced subtitle tracks; HLS subtitle
  /// variants are usually DEFAULT=NO, so a stream that HAS subtitles would
  /// never show them without an explicit selection (2026-08: "movies have no
  /// subtitles"). The user's own toggle / settings take over afterwards.
  bool _subtitleAutoSelected = false;

  /// One-shot toast channel to the controls overlay: external-subtitle load
  /// outcomes are surfaced so "no subtitles" is never a silent failure
  /// (2026-08: the fetch failed quietly on iOS builds without a TMDB key).
  final ValueNotifier<String?> _subtitleNotice = ValueNotifier<String?>(null);

  /// True once the external-subtitle outcome toast has been shown (one per
  /// session, so a resume doesn't re-toast).
  bool _subsResultShown = false;

  /// Watch-progress save throttle: the position stream emits very often, so
  /// progress is persisted at most every [progressSaveInterval] while playing.
  static const Duration progressSaveInterval = Duration(seconds: 5);
  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);

  /// True while this screen is the active fullscreen player (wakelock + saved
  /// screen brightness apply only then — when minimized, the user browses the
  /// app, so the screen may sleep normally).
  bool _wakelockHeld = false;

  /// YouTube-style portrait inline mode: the video renders as a 16:9 box in
  /// PORTRAIT orientation with the movie info below (no immersive bars), and
  /// a swipe down pops it into the floating mini player — exactly like
  /// YouTube's "small player" view.
  bool _portraitMode = false;

  /// True when this session changed the system brightness via the player's
  /// left-edge vertical-drag gesture; the system value is restored on exit.
  bool _brightnessChanged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enterLandscape();
    });
    _initPlayer();
    // Keep the screen awake while the movie plays (2026-08 request) and take
    // over brightness control for the volume/brightness gestures.
    WakelockPlus.enable();
    _wakelockHeld = true;
  }

  /// Acquires the playback session from [MiniPlayerService] — creating a
  /// fresh native Player, or REUSING the one still playing in the mini
  /// player (tap-to-expand resumes seamlessly: same Player, same position,
  /// no re-open).
  Future<void> _initPlayer() async {
    final session = await MiniPlayerService.instance.acquire(
      url: widget.args.url,
      title: widget.args.title,
      sourceLabel: widget.args.sourceLabel,
      httpHeaders: widget.args.httpHeaders,
      tmdbId: widget.args.tmdbId,
    );
    if (!mounted) return;
    _player = session.player;
    _videoController = session.videoController;
    setState(() {}); // now the controls overlay can render
    _listenForErrors();
    _listenForPlayback();
    if (session.fresh) {
      await _open();
      // Streams rarely carry subtitle tracks (2vcdn has none) — fetch an
      // EXTERNAL subtitle (Indonesian, keyless YIFY) in the background so
      // playback is never delayed by it.
      unawaited(_loadExternalSubtitles());
    } else {
      // Resumed from the mini player: seed the playback evidence from the
      // LIVE position. If the stream already advanced past zero it is proven
      // to run (failure gating must not treat it as a stall); if the user
      // minimized before the first frame, keep the startup watchdog alive so
      // a never-starting stream still fails over.
      final pos = _player.state.position;
      _sawPlaying = pos > Duration.zero;
      _lastPosition = pos;
      _currentPosition = pos;
      _lastWatchPosition = pos;
      _startWatchdogs(withStartup: !_sawPlaying);
      appLog('FILMKU_MPV_RESUMED', '(mini player → fullscreen)');
      // Resume path: if the session never attached external subs (e.g. the
      // fetch failed while the screen was up) and the stream still has none,
      // try again.
      unawaited(_loadExternalSubtitles());
    }
  }

  /// Fetches an EXTERNAL subtitle for the movie (Indonesian preferred, then
  /// English) and attaches it via media_kit's `SubtitleTrack.data`. Only runs
  /// when the stream itself has NO subtitle tracks (native wins). Background
  /// best-effort: any failure is swallowed — playback is never affected.
  Future<void> _loadExternalSubtitles() async {
    final tmdbId = widget.args.tmdbId;
    if (tmdbId == null || _failed) return;
    // The stream already carries REAL subtitle tracks — native wins.
    //
    // 2026-08 on-device root cause (Redmi Note 8 Pro): 2vcdn streams report
    // `subtitle=2` PHANTOM tracks — their `#EXT-X-MEDIA` lists carry no
    // subtitle variants at all (verified from the live master/variant), so
    // mpv enumerates empty tracks with NO title (`autoSelected=(no title)`).
    // The old `isNotEmpty` gate then SKIPPED the external-subtitle fetch
    // (the only real subtitle source), leaving the movie with nothing to
    // render. Only tracks with a meaningful title/language are treated as
    // real; title-less placeholders fall through to the external fetch.
    if (_hasRealSubtitleTracks(_player.state.tracks.subtitle)) return;
    try {
      // Live-verified 2026-08: the YIFY chain (4 sequential HTTP calls incl.
      // the Cloudflare-protected .zip) resolves in ~1.4s from a wired
      // connection but can be much slower on mobile networks — 20s was too
      // tight and killed the fetch before it finished (the symptom: "no
      // subtitles" while the laptop probe succeeds). 40s keeps it best-
      // effort (background, never blocks playback) but survives mobile.
      appLog(
          'FILMKU_SUBS_START',
          'tmdbId=$tmdbId title=${widget.args.title} '
              'year=${widget.args.movieYear ?? '-'} imdb=${widget.args.imdbId ?? '-'}');
      final sub = await SubtitleDatasource()
          .fetchSubtitleFromMeta(
            tmdbId: tmdbId,
            title: widget.args.title,
            year: widget.args.movieYear,
            imdbId: widget.args.imdbId,
          )
          .timeout(const Duration(seconds: 40));
      if (!mounted || _failed || sub == null) {
        appLog('FILMKU_SUBS_NULL',
            'tmdbId=$tmdbId mounted=$mounted failed=$_failed');
        _notifySubsResult(false);
        return;
      }
      // Re-check after the fetch: REAL native tracks may have appeared in
      // the meantime (or the user closed / playback failed over). Same
      // phantom-track filter as above — 2vcdn's title-less placeholders must
      // not block the external subtitle we just fetched.
      if (_hasRealSubtitleTracks(_player.state.tracks.subtitle)) return;
      await _player.setSubtitleTrack(
        SubtitleTrack.data(sub.data, title: sub.title, language: sub.language),
      );
      appLog(
        'FILMKU_SUBS',
        'loaded ${sub.language} ${sub.data.length} chars tmdbId=$tmdbId',
      );
      _notifySubsResult(true, language: sub.language);
    } catch (error) {
      appLog('FILMKU_SUBS', 'failed tmdbId=$tmdbId $error');
      _notifySubsResult(false);
    }
  }

  /// Whether [tracks] carries REAL subtitle tracks — i.e. any track with a
  /// meaningful title/language. 2vcdn streams report `subtitle=2` PHANTOM
  /// tracks (their `#EXT-X-MEDIA` lists carry no subtitle variants at all),
  /// so mpv enumerates empty tracks with no title; those must not block the
  /// external-subtitle fetch (the only real subtitle source).
  bool _hasRealSubtitleTracks(List<SubtitleTrack> tracks) => tracks.any((t) {
        final title = t.title?.trim() ?? '';
        return title.isNotEmpty && title != 'Undetermined';
      });

  /// Surfaces the external-subtitle outcome ONCE per session as an overlay
  /// toast — success shows the language, failure says no subtitle was found
  /// (instead of the old silent null → "no subtitles" mystery).
  void _notifySubsResult(bool ok, {String? language}) {
    if (_subsResultShown || !mounted) return;
    _subsResultShown = true;
    _subtitleNotice.value = ok
        ? ((language == null || language.isEmpty)
            ? 'Subtitle dimuat.'
            : 'Subtitle $language dimuat.')
        : 'Subtitel tidak ditemukan untuk film ini.';
  }

  Future<void> _open() async {
    appLog(
      'FILMKU_MPV_OPEN',
      'url=${widget.args.url} startAt=${widget.args.startAt.inMilliseconds}',
    );
    // Fresh attempt: clear playback evidence so the error gating and the
    // startup watchdog evaluate THIS run, not the previous (retry) one.
    _sawPlaying = false;
    _lastPosition = Duration.zero;
    _currentPosition = Duration.zero;
    _lastWatchPosition = Duration.zero;
    _silentFreezeConsecutive = 0;
    _subtitleAutoSelected = false;
    _errorGraceTimer?.cancel();
    try {
      // Resume-safe open: open PAUSED, seek to the resume position, THEN
      // play. Opening with `play: true` and seeking right after races mpv's
      // async load for a network stream — the autoplay may buffer from 0 and
      // the seek gets dropped, which read as "Lanjutkan menonton starts from
      // the beginning" (2026-08). Paused-open → seek → play is deterministic.
      await _player.open(
        Media(
          widget.args.url,
          httpHeaders: widget.args.httpHeaders,
        ),
        play: false,
      );
      if (widget.args.startAt > Duration.zero) {
        await _player.seek(widget.args.startAt);
        appLog(
          'FILMKU_MPV_SEEKED',
          'to=${widget.args.startAt.inMilliseconds}ms '
              'movieId=${widget.args.tmdbId}',
        );
      }
      await _player.play();
      appLog('FILMKU_MPV_OPENED', '');
      _startWatchdogs();
    } catch (e) {
      appLog('FILMKU_MPV_OPEN_ERROR', '$e');
      // Open threw (bad/unsupported URL) — the stream can never start, so
      // auto-failover to the backup player rather than a dead-end error UI.
      _startupFailed('Failed to open stream.');
    }
  }

  /// Starts the startup + silent-freeze watchdogs.
  ///
  /// - Startup ([withStartup]): if the stream never starts playing,
  ///   auto-failover to the backup player instead of staring at black: a
  ///   brief notice, then pop with failed=true so PlayerScreen continues in
  ///   the visible WebView (which is proven to play these CDN streams
  ///   on-device). Skipped for a resumed mini-player session (already
  ///   playing).
  /// - Silent freeze: catches a stream that dies silently (no error event,
  ///   but position stops advancing while still `playing`).
  void _startWatchdogs({bool withStartup = true}) {
    if (withStartup) {
      _startupWatchdog?.cancel();
      _startupWatchdog = Timer(_startupTimeout, () {
        if (mounted && !_sawPlaying) {
          appLog('FILMKU_MPV_STARTUP_TIMEOUT', '(no playback in 12s)');
          _startupFailed('Stream did not start playing.');
        }
      });
    }
    _silentFreezeWatchdog?.cancel();
    _silentFreezeWatchdog = Timer.periodic(_silentFreezePeriod, (_) {
      final frozen = mounted &&
          !_failed &&
          MpvPlayerScreen.shouldSurfaceSilentFreeze(
            playing: _player.state.playing,
            sawPlaying: _sawPlaying,
            currentPosition: _currentPosition,
            lastWatchPosition: _lastWatchPosition,
          );
      if (frozen) {
        // Require TWO consecutive frozen ticks before surfacing: a single
        // 20s window can be a slow-network rebuffer (mpv `playing` stays
        // true while it rebuffers), not a dead stream.
        _silentFreezeConsecutive++;
        if (_silentFreezeConsecutive >= 2) {
          appLog(
            'FILMKU_MPV_SILENT_FREEZE',
            '(no movement over ${_silentFreezePeriod.inSeconds * 2}s)',
          );
          _markFailed('Playback stalled (no progress).');
        }
      } else {
        _silentFreezeConsecutive = 0;
      }
      _lastWatchPosition = _currentPosition;
    });
  }

  /// Auto-fails a stream that never started (startup timeout / open error).
  ///
  /// Shows a short "switching to backup player…" notice, then pops with
  /// `failed=true` so [PlayerScreen] continues in the visible WebView
  /// fallback — the path proven to actually play these CDN streams on-device
  /// (the user's iOS flow: mpv direct URL loads forever → WebView plays →
  /// hands back to mpv with a working captured URL). Without this the screen
  /// parked on the full error UI over a still-loading player and required a
  /// manual tap to escape.
  void _startupFailed(String detail) {
    if (!mounted || _failed) return;
    setState(() {
      _failed = true;
      _autoFailover = true;
      _failoverDetail = detail;
    });
    appLog('FILMKU_MPV_STARTUP_FAIL', detail);
    _failoverTimer?.cancel();
    _failoverTimer = Timer(MpvPlayerScreen.failoverNoticeDuration, () {
      if (mounted) _close(failed: true);
    });
  }

  void _listenForErrors() {
    _errorSub = _player.stream.error.listen(_onError);
  }

  /// Handles a media-kit error.
  ///
  /// - No evidence of playback yet → surface the failure immediately (the
  ///   stream never started).
  /// - Error WHILE playback is progressing → give it a short grace window
  ///   ([_errorGracePeriod]): if the position keeps advancing the error was
  ///   transient (a dropped segment) and is ignored (the 2026-08 iOS bug:
  ///   error UI over a still-playing movie); if it stalls, surface it so the
  ///   user isn't stuck on a frozen frame.
  void _onError(String error) {
    appLog('FILMKU_MPV_ERROR', error);
    if (MpvPlayerScreen.shouldSurfaceFailure(
      sawPlaying: _sawPlaying,
      lastPosition: _lastPosition,
    )) {
      // Stream NEVER started (no playing event, no position) — e.g. the
      // signed CDN URL is rejected/refused before the 12s watchdog fires.
      // Auto-failover to the backup player instead of parking the full
      // "Native playback failed" UI over a still-loading player (the exact
      // symptom reported on iOS 2026-08). Consistent with the watchdog and
      // open-error paths.
      _startupFailed('Playback error: $error');
      return;
    }
    appLog('FILMKU_MPV_ERROR_GRACE_START', '(waiting for progress)');
    // Keep the ORIGINAL deadline if a grace window is already armed — a
    // stream emitting errors every few seconds (with no progress) must still
    // surface the stall, not push detection out forever by restarting.
    if (_errorGraceTimer?.isActive ?? false) {
      appLog('FILMKU_MPV_ERROR_GRACE_ALREADY_ARMED', '(keeping deadline)');
      return;
    }
    final posAtError = _lastPosition;
    _errorGraceTimer = Timer(_errorGracePeriod, () {
      // Don't call it a stall when the user deliberately paused — position
      // won't advance by design, and a fake "Playback stalled" overlay over
      // a paused video is exactly the bug class we're fixing (2026-08).
      // PlayerState.playing is a plain bool in media_kit 1.2.6 (read the
      // current instantaneous state; the stream is the reactive source).
      //
      // Deliberate trade-off: a fatal mid-playback error that ALSO flips
      // `playing` to false (e.g. the CDN kills the stream) is swallowed here
      // — the user keeps the frozen frame without a retry UI rather than a
      // fake overlay over a paused/working video. That's the bug class we're
      // fixing; retry is still reachable via the top-bar close button.
      if (mounted &&
          !_failed &&
          _player.state.playing &&
          _lastPosition <= posAtError) {
        if (MpvPlayerScreen.shouldAutoFailoverOnStall(
            lastPosition: _lastPosition)) {
          // Never actually played (position never advanced past zero): the
          // CDN rejected the stream before the first frame (vidlink's signed
          // URLs → 403/428). Auto-failover to the backup player instead of
          // parking the full error UI over a still-loading player — the
          // exact symptom on iOS, 2026-08. Consistent with the startup
          // timeout / open-error / pre-start error paths.
          _startupFailed('Playback error: $error');
        } else {
          appLog(
            'FILMKU_MPV_ERROR_STALLED',
            '(no progress in ${_errorGracePeriod.inSeconds}s) error=$error',
          );
          _markFailed('Playback stalled: $error');
        }
      }
    });
  }

  /// Tracks real progress. IMPORTANT (2026-08 root cause): the libmpv
  /// `playing` event fires while the stream is STILL LOADING (the core is not
  /// idle while it fetches the master playlist), so `playing` alone must NOT
  /// mark the stream as started — a CDN reject (vidlink's signed URLs →
  /// 403/428) would otherwise cancel the startup watchdog and the error path
  /// would park the full error UI over a still-loading player. "Started" is
  /// therefore defined ONLY by the position advancing past zero (real first
  /// frame / first progress).
  void _listenForPlayback() {
    _playingSub = _player.stream.playing.listen((playing) {
      // Deliberately empty: see the doc above. Real start is decided in the
      // position listener.
    });
    // Track diagnostics (2026-08, v1.3.17): the "no subtitles" complaints
    // need on-device proof of what the stream actually carries. Most 2vcdn
    // streams have NO subtitle track at all — the log line tells us whether
    // libass has anything to render or the stream simply has none.
    _tracksSub = _player.stream.tracks.listen((t) {
      appLog(
        'FILMKU_MPV_TRACKS',
        'video=${t.video.length} audio=${t.audio.length} '
            'subtitle=${t.subtitle.length} '
            'subTitles=${t.subtitle.map((s) => s.title ?? '?').join('|')}',
      );
      // Auto-select the first subtitle track so subtitles show by DEFAULT
      // when the stream carries them (libmpv only auto-enables DEFAULT/
      // forced tracks; HLS subtitle variants are usually DEFAULT=NO). One-
      // shot per open — the user's toggle/settings take over afterwards.
      if (t.subtitle.isNotEmpty && !_subtitleAutoSelected) {
        _subtitleAutoSelected = true;
        _player.setSubtitleTrack(t.subtitle.first);
        appLog(
          'FILMKU_MPV_SUBTRACK',
          'autoSelected=${t.subtitle.first.title ?? '(no title)'}',
        );
      }
    });
    _positionSub = _player.stream.position.listen((position) {
      // RAW current position — updates on every event, including backward
      // seeks, so the silent-freeze watchdog compares true progress (not a
      // monotonic high-watermark that never decreases).
      _currentPosition = position;
      if (position > Duration.zero && !_sawPlaying) {
        // First real progress — the stream genuinely started. Cancelling the
        // startup watchdog here (not on `playing`) keeps the 12s failover
        // alive for streams that never answer while never killing one that
        // is simply buffering its first frames.
        _sawPlaying = true;
        _startupWatchdog?.cancel();
        appLog('FILMKU_MPV_PLAYING', '(position advanced past zero)');
        // Full watch history: record this play ONCE per session, on the
        // first real frame (a stream that never started must not pollute the
        // history).
        _recordHistory();
      }
      if (position > _lastPosition) {
        _lastPosition = position;
        // Real progress while an error grace window is open ⇒ the error was
        // transient; cancel the stall timer.
        _errorGraceTimer?.cancel();
      }
      // Continue-watching: persist position throttled while playing (the
      // stream emits position far more often than we want to write to Hive).
      final now = DateTime.now();
      if (position > Duration.zero &&
          now.difference(_lastProgressSave) >= progressSaveInterval) {
        _lastProgressSave = now;
        _saveProgress();
      }
    });
  }

  void _markFailed(String detail) {
    if (!mounted || _failed) return;
    setState(() {
      _failed = true;
    });
    appLog('FILMKU_MPV_FAILED', detail);
  }

  @override
  void dispose() {
    _startupWatchdog?.cancel();
    _silentFreezeWatchdog?.cancel();
    _errorGraceTimer?.cancel();
    _failoverTimer?.cancel();
    _errorSub?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _tracksSub?.cancel();
    _subtitleNotice.dispose();
    // Persist where the user stopped (continue-watching), then release the
    // screen-awake lock + restore the system brightness.
    _saveProgress();
    if (_wakelockHeld) {
      WakelockPlus.disable();
      _wakelockHeld = false;
    }
    if (_brightnessChanged) {
      ScreenBrightness().resetApplicationScreenBrightness();
      _brightnessChanged = false;
    }
    _restorePortrait();
    // Player + local HLS relay lifecycle is owned by MiniPlayerService so the
    // mini player keeps playing after this route pops. Only a pop that was
    // NOT a minimize stops playback (system back on Android, failed close).
    if (!MiniPlayerService.instance.isMinimized) {
      MiniPlayerService.instance.stop();
    }
    super.dispose();
  }

  /// Records this play in the full watch history (once per session — called
  /// only from the first-real-frame branch of the position listener).
  void _recordHistory() {
    final tmdbId = widget.args.tmdbId;
    if (tmdbId == null) return;
    WatchHistoryService.instance.record(
      movieId: tmdbId,
      title: widget.args.title,
      posterPath: widget.args.posterPath,
    );
  }

  /// Persists the current playback position for continue-watching (throttled
  /// while playing; always saved on dispose). The entry is auto-cleared by the
  /// service when the movie is essentially finished.
  void _saveProgress() {
    final tmdbId = widget.args.tmdbId;
    if (tmdbId == null) return;
    final pos = _player.state.position;
    final dur = _player.state.duration;
    if (pos <= Duration.zero) return;
    WatchProgressService.instance.save(
      movieId: tmdbId,
      title: widget.args.title,
      posterPath: widget.args.posterPath,
      position: pos,
      duration: dur,
    );
  }

  Future<void> _enterLandscape() async {
    // EXPLICIT native landscape first: on MIUI with the system auto-rotate
    // OFF, Flutter's sensor-based setPreferredOrientations is ignored and the
    // player stays portrait (video small in the middle, bottom bar never at
    // the bottom — the "controls in the middle" complaint, 2026-08).
    // setRequestedOrientation(LANDSCAPE) is honored regardless.
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

  /// Closes the player: stops playback (unless already minimized — then the
  /// mini player keeps the session) and pops with [failed] for the caller.
  Future<void> _close({bool failed = false}) async {
    if (failed || !MiniPlayerService.instance.isMinimized) {
      await MiniPlayerService.instance.stop();
    }
    if (mounted) context.pop<bool>(failed);
  }

  /// Toggles the YouTube-style portrait inline mode.
  ///
  /// Portrait: restore orientation + edge-to-edge UI (no immersive bars) so
  /// the video renders in a 16:9 box with the movie info below. Fullscreen:
  /// force landscape + immersive (the default player experience).
  Future<void> _togglePortrait() async {
    setState(() => _portraitMode = !_portraitMode);
    if (_portraitMode) {
      await OrientationChanger.restore();
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      await _enterLandscape();
    }
  }

  /// "Pop up film": keeps playback running in the floating mini player.
  void _minimize() {
    // Never minimize a stream that NEVER started (auto-failover notice): the
    // mini player would spin a dead stream forever and the WebView failover
    // (PlayerScreen's backup path) would never run. Close with failure so the
    // caller continues in the visible WebView as designed.
    if (_autoFailover) {
      _close(failed: true);
      return;
    }
    MiniPlayerService.instance.minimize();
    context.pop<bool>(false);
  }

  /// The player surface: the video + the full controls overlay. In fullscreen
  /// it fills the screen; in portrait mode it's the 16:9 box at the top.
  Widget _buildPlayerSurface() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Custom full-featured controls — pause, mute, subtitles and a
        // settings sheet (speed, subtitle size, resolution, audio) plus
        // the top bar (minimize, close, title, source chip). Identical
        // on iOS and Android. Positioned.fill pins the overlay to the
        // FULL screen edge-to-edge so no stale parent inset can squeeze
        // the controls off the bottom.
        Positioned.fill(
          child: _videoController != null
              ? MpvControlsOverlay(
                  controller: _videoController!,
                  title: widget.args.title,
                  sourceLabel: widget.args.sourceLabel,
                  onMinimize: _minimize,
                  onClose: _close,
                  onTogglePortrait: _togglePortrait,
                  portraitMode: _portraitMode,
                  notice: _subtitleNotice,
                )
              : const ColoredBox(color: Colors.black),
        ),
        if (_failed && _autoFailover)
          // Stream never started — auto-switching to the backup player.
          // COMPACT card pinned to the UPPER area (below the top bar), NOT
          // centered: a centered card sat over the middle of the still-
          // loading video — the exact "controls in the middle" complaint
          // (2026-08). The video stays fully visible; the real CDN error
          // (e.g. "HTTP 428") is shown underneath so the user sees WHY
          // before the screen auto-pops into the WebView fallback.
          Align(
            alignment: const Alignment(0, -0.7),
            child: Material(
              color: const Color(0xE616181D),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white70),
                    const SizedBox(height: 14),
                    const Text(
                      'Stream tidak dapat dimulai — '
                      'beralih ke pemutar cadangan…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    if (_failoverDetail.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _failoverDetail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        if (_failed && !_autoFailover)
          // Compact card pinned to the UPPER area (below the top bar), NOT
          // centered — a centered card over the middle of the video is
          // the "controls in the middle" complaint (2026-08). The video
          // keeps playing behind and the X / PiP stay usable; Retry /
          // Back-to-WebView remain pressable (they're in the card, on
          // top).
          Align(
            alignment: const Alignment(0, -0.7),
            child: Material(
              color: const Color(0xF016181D),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                child: ErrorView(
                  compact: true,
                  message:
                      'Native playback failed for ${widget.args.sourceLabel}.',
                  onRetry: () {
                    setState(() {
                      _failed = false;
                      _autoFailover = false;
                    });
                    _open();
                  },
                  secondaryLabel: 'Back to WebView',
                  onSecondary: () => _close(failed: true),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// YouTube-style portrait inline mode: the 16:9 video box at the top with
  /// the MOVIE DESCRIPTION below (title, meta, rating, genres, overview —
  /// the same info as the Detail screen, NOT a bare placeholder). Swipe down
  /// anywhere pops it into the floating mini player — like YouTube's small
  /// player. In fullscreen mode the player fills the screen as before.
  Widget _buildPortraitBody() {
    return SafeArea(
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _buildPlayerSurface(),
          ),
          // Movie description below the video — fetched from TMDB via the
          // same provider the Detail screen uses, so the portrait view is the
          // film's real description, not a separate empty "tab".
          Expanded(
            child: _PortraitMovieInfo(
              movieId: widget.args.tmdbId,
              fallbackTitle: widget.args.title,
              sourceLabel: widget.args.sourceLabel,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // resizeToAvoidBottomInset: false — a video player has no text input,
      // so the body must never be shrunk by any viewInset (a transient
      // keyboard inset on some ROMs would otherwise compress the player).
      resizeToAvoidBottomInset: false,
      // In fullscreen there is NO outer SafeArea (immersive mode hides the
      // system bars; the overlay bars handle their own insets). In portrait
      // mode the movie info below the video DOES need the SafeArea.
      body: PlayerSwipeDismiss(
        // Swipe down = "pop up film" (minimize, keep playing) — on every
        // platform (2026-08: the user tests on Android first, and the
        // YouTube-style portrait flow needs the swipe on Android too). Full
        // close stays the X button (or the system back).
        onDismiss: _minimize,
        child: _portraitMode ? _buildPortraitBody() : _buildPlayerSurface(),
      ),
    );
  }
}

/// The movie description shown BELOW the video in portrait mode — the same
/// info as the Detail screen (poster, title, year • runtime, rating, genres,
/// overview), so the portrait view reads as the film's description page, not
/// a separate bare tab (2026-08 user feedback). Falls back to the player's
/// title/source when TMDB details aren't available (no API key / offline).
class _PortraitMovieInfo extends ConsumerWidget {
  const _PortraitMovieInfo({
    required this.movieId,
    required this.fallbackTitle,
    required this.sourceLabel,
  });

  final int? movieId;
  final String fallbackTitle;
  final String sourceLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = movieId;
    if (id == null) {
      return _fallback(fallbackTitle, sourceLabel);
    }
    final details = ref.watch(movieDetailsProvider(id));
    return details.when(
      loading: () => _fallback(fallbackTitle, sourceLabel),
      error: (error, stackTrace) => _fallback(fallbackTitle, sourceLabel),
      data: (data) {
        final movie = data.movie;
        final year = Formatters.formatDate(movie.releaseDate);
        final runtime = Formatters.formatRuntime(data.runtime);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 90,
                      height: 130,
                      child: movie.posterPath == null
                          ? Container(
                              color: AppColors.surface,
                              child: const Center(
                                child: Icon(Icons.movie_outlined,
                                    color: AppColors.textMuted),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: ApiConstants.image(
                                  ApiConstants.posterSize, movie.posterPath!),
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: AppColors.surface,
                              ),
                              errorWidget: (context, url, error) =>
                                  Container(color: AppColors.surface),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          movie.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$year • $runtime',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.star,
                                size: 16, color: AppColors.star),
                            const SizedBox(width: 4),
                            Text(
                              Formatters.formatVote(movie.voteAverage),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '(${data.voteCount} votes)',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          sourceLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (data.genres.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: data.genres
                      .map((genre) => Chip(
                            label: Text(genre),
                            backgroundColor: AppColors.surfaceLight,
                            side: BorderSide.none,
                            labelStyle: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ))
                      .toList(),
                ),
              ],
              if (data.tagline != null && data.tagline!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  data.tagline!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                movie.overview.isEmpty
                    ? 'No synopsis available.'
                    : movie.overview,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Icon(Icons.swipe_down_alt_rounded,
                      color: AppColors.textMuted, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Geser ke bawah untuk memunculkan mini player — '
                      'putar terus berjalan.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Bare-bones fallback when TMDB details are unavailable (no API key /
  /// offline): the player's own title + source, so the portrait view never
  /// looks broken.
  Widget _fallback(String title, String sourceLabel) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sourceLabel,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.swipe_down_alt_rounded,
                  color: Colors.white38, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Geser ke bawah untuk memunculkan mini player — '
                  'putar terus berjalan.',
                  style: TextStyle(color: Colors.white38, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
