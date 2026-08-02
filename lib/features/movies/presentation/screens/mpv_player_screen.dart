import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../widgets/error_view.dart';
import '../widgets/player_swipe_dismiss.dart';

/// Arguments for the mpv native player route (WebView handoff streams).
class MpvPlayerArgs {
  const MpvPlayerArgs({
    required this.url,
    required this.title,
    required this.sourceLabel,
    this.startAt = Duration.zero,
    this.httpHeaders = const <String, String>{},
  });

  /// Direct `.m3u8`/`.mp4` URL captured from inside the WebView fallback.
  final String url;

  /// Movie title shown in the top bar.
  final String title;

  /// Human-readable provider name.
  final String sourceLabel;

  /// Where the WebView playback was, to resume from.
  final Duration startAt;

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

  @override
  State<MpvPlayerScreen> createState() => _MpvPlayerScreenState();
}

class _MpvPlayerScreenState extends State<MpvPlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  bool _failed = false;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;

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

  @override
  void initState() {
    super.initState();
    // Android performance (2026-08): the default demuxer cache is 32MB;
    // a larger cache smooths slow CDNs (less stutter/"patah"). Hardware
    // acceleration is on by default (GPU decode) — kept explicit so it's
    // never silently disabled by a config change.
    _player = Player(
      configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
    );
    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enterLandscape();
    });
    _listenForErrors();
    _listenForPlayback();
    _open();
  }

  Future<void> _open() async {
    debugPrint(
      'FILMKU_MPV_OPEN url=${widget.args.url} '
      'startAt=${widget.args.startAt.inMilliseconds}',
    );
    // Fresh attempt: clear playback evidence so the error gating and the
    // startup watchdog evaluate THIS run, not the previous (retry) one.
    _sawPlaying = false;
    _lastPosition = Duration.zero;
    _currentPosition = Duration.zero;
    _lastWatchPosition = Duration.zero;
    _silentFreezeConsecutive = 0;
    _errorGraceTimer?.cancel();
    try {
      await _player.open(
        Media(
          widget.args.url,
          httpHeaders: widget.args.httpHeaders,
        ),
        play: true,
      );
      if (widget.args.startAt > Duration.zero) {
        await _player.seek(widget.args.startAt);
      }
      debugPrint('FILMKU_MPV_OPENED');
      // If the stream never starts playing, surface the failure so the user
      // can retry / go back to the WebView instead of staring at black.
      _startupWatchdog?.cancel();
      _startupWatchdog = Timer(_startupTimeout, () {
        if (mounted && !_sawPlaying) {
          debugPrint('FILMKU_MPV_STARTUP_TIMEOUT (no playback in 12s)');
          _markFailed('Stream did not start playing.');
        }
      });
      // Periodic progress watchdog: catches a stream that dies silently
      // (no error event, but position stops advancing while still `playing`).
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
            debugPrint('FILMKU_MPV_SILENT_FREEZE '
                '(no movement over ${_silentFreezePeriod.inSeconds * 2}s)');
            _markFailed('Playback stalled (no progress).');
          }
        } else {
          _silentFreezeConsecutive = 0;
        }
        _lastWatchPosition = _currentPosition;
      });
    } catch (e) {
      debugPrint('FILMKU_MPV_OPEN_ERROR $e');
      _markFailed('Failed to open stream.');
    }
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
    debugPrint('FILMKU_MPV_ERROR $error');
    if (MpvPlayerScreen.shouldSurfaceFailure(
      sawPlaying: _sawPlaying,
      lastPosition: _lastPosition,
    )) {
      _markFailed('Playback error: $error');
      return;
    }
    debugPrint('FILMKU_MPV_ERROR_GRACE_START (waiting for progress)');
    // Keep the ORIGINAL deadline if a grace window is already armed — a
    // stream emitting errors every few seconds (with no progress) must still
    // surface the stall, not push detection out forever by restarting.
    if (_errorGraceTimer?.isActive ?? false) {
      debugPrint('FILMKU_MPV_ERROR_GRACE_ALREADY_ARMED (keeping deadline)');
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
        debugPrint('FILMKU_MPV_ERROR_STALLED '
            '(no progress in ${_errorGracePeriod.inSeconds}s)');
        _markFailed('Playback stalled: $error');
      }
    });
  }

  /// Tracks real progress: playing=true marks the stream as genuinely
  /// started (transient errors after that are ignored); position advances
  /// confirm progress for [MpvPlayerScreen.shouldSurfaceFailure].
  void _listenForPlayback() {
    _playingSub = _player.stream.playing.listen((playing) {
      if (playing && !_sawPlaying) {
        _sawPlaying = true;
        _startupWatchdog?.cancel();
        debugPrint('FILMKU_MPV_PLAYING');
      }
    });
    _positionSub = _player.stream.position.listen((position) {
      // RAW current position — updates on every event, including backward
      // seeks, so the silent-freeze watchdog compares true progress (not a
      // monotonic high-watermark that never decreases).
      _currentPosition = position;
      if (position > _lastPosition) {
        _lastPosition = position;
        // Real progress while an error grace window is open ⇒ the error was
        // transient; cancel the stall timer.
        _errorGraceTimer?.cancel();
      }
    });
  }

  void _markFailed(String detail) {
    if (!mounted || _failed) return;
    setState(() {
      _failed = true;
    });
    debugPrint('FILMKU_MPV_FAILED $detail');
  }

  @override
  void dispose() {
    _startupWatchdog?.cancel();
    _silentFreezeWatchdog?.cancel();
    _errorGraceTimer?.cancel();
    _errorSub?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _restorePortrait();
    _player.dispose();
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

  void _close({bool failed = false}) => context.pop<bool>(failed);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        // iOS: swipe down anywhere to leave fullscreen (no need to kill the
        // app from the background). Non-iOS platforms are a pass-through.
        child: PlayerSwipeDismiss(
          onDismiss: () => _close(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // libmpv renders + letterboxes; the built-in adaptive controls
              // provide play/pause, seek bar and volume.
              Video(controller: _videoController),
              // Title + source chip + close — always accessible (immersive
              // mode hides the system affordances).
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(
                  children: [
                    _RoundIconButton(
                      icon: Icons.close,
                      tooltip: 'Close player',
                      onPressed: () => _close(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.args.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        widget.args.sourceLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_failed)
                Center(
                  child: ErrorView(
                    message:
                        'Native playback failed for ${widget.args.sourceLabel}.',
                    onRetry: () {
                      setState(() => _failed = false);
                      _open();
                    },
                    secondaryLabel: 'Back to WebView',
                    onSecondary: () => _close(failed: true),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
