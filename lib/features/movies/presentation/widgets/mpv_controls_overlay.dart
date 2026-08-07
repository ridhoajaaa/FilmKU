import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../../../core/local/settings_service.dart';

/// Formats a [Duration] as `h:mm:ss` (hours present only when >= 1 hour) or
/// `m:ss`. Exposed for tests.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

/// Full-featured player controls overlay (replaces media_kit's built-in
/// adaptive controls, which render minimal on iOS).
///
/// Identical on every platform — pause, ±5s seek, seek bar + time, mute,
/// subtitles and a settings sheet (playback speed, subtitle size, video
/// quality/resolution, audio track) — plus the top bar (minimize to mini
/// player, close, title, source chip) and a tap-to-toggle / auto-hide
/// behavior.
class MpvControlsOverlay extends StatefulWidget {
  const MpvControlsOverlay({
    super.key,
    required this.controller,
    required this.title,
    required this.sourceLabel,
    required this.onMinimize,
    required this.onClose,
    this.onTogglePortrait,
    this.portraitMode = false,
    this.notice,
  });

  final VideoController controller;
  final String title;
  final String sourceLabel;

  /// Minimize to the floating mini player (playback continues).
  final VoidCallback onMinimize;

  /// Fully close the player (playback stops).
  final VoidCallback onClose;

  /// Toggles the YouTube-style portrait inline mode (null hides the button).
  final VoidCallback? onTogglePortrait;

  /// Whether the player is currently in portrait inline mode (the top bar
  /// shows the "enter fullscreen" icon instead of "exit fullscreen").
  final bool portraitMode;

  /// One-shot toast channel from the owning screen (external-subtitle load
  /// outcomes). Non-null values are shown as a brief toast in the UPPER
  /// area (below the top bar), never centered.
  final ValueNotifier<String?>? notice;

  /// Speed presets offered in the settings sheet. Exposed for tests.
  static const List<double> speedOptions = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  /// Subtitle font-size range. Exposed for tests.
  static const double minSubtitleSize = 20;
  static const double maxSubtitleSize = 52;

  /// Step used by the rewind/forward buttons.
  static const Duration seekStep = Duration(seconds: 5);

  /// Step used by the double-tap seek gesture (left/right screen sides).
  static const Duration gestureSeekStep = Duration(seconds: 10);

  /// Maps an x-offset (logical px) to a horizontal third of [width] — the
  /// double-tap seek zones: left third = rewind, right third = forward,
  /// middle = no-op. Exposed for tests.
  static SeekZone seekZoneFor(double x, double width) {
    if (width <= 0) return SeekZone.middle;
    final third = width / 3;
    if (x < third) return SeekZone.left;
    if (x > width - third) return SeekZone.right;
    return SeekZone.middle;
  }

  /// Clamps [position] + [delta] to the playable range `[0, duration]` — the
  /// target of a ±[seekStep] seek. A zero/unknown duration disables the upper
  /// clamp (mpv hasn't reported the real length yet). Exposed for tests.
  static Duration clampSeekTarget(
    Duration position,
    Duration delta,
    Duration duration,
  ) {
    final target = position + delta;
    if (target < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && target > duration) return duration;
    return target;
  }

  /// Left half of the screen = brightness; right half = volume (MX-Player
  /// style). Exposed for tests.
  static VerticalDragSide dragSideFor(Offset pos, double width) {
    if (width <= 0) return VerticalDragSide.volume;
    return pos.dx < width / 2
        ? VerticalDragSide.brightness
        : VerticalDragSide.volume;
  }

  @override
  State<MpvControlsOverlay> createState() => _MpvControlsOverlayState();
}

class _MpvControlsOverlayState extends State<MpvControlsOverlay> {
  late final Player _player = widget.controller.player;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100;
  double _rate = 1.0;
  bool _muted = false;
  double _lastVolume = 100;

  /// True while a restored mute (setVolume(0) fired before the volume stream
  /// settled) is still being applied. Stale pre-restore volume events — e.g.
  /// the initial 100 emitted on subscribe — must not flip the icon back to
  /// unmuted while the real mute event is in flight.
  bool _restoringMute = false;

  bool _dragging = false;
  double _dragValue = 0;

  /// Brief centered toast (subtitle feedback etc.) — visible over the
  /// immersive fullscreen player, unlike a bottom SnackBar.
  String? _toast;
  Timer? _toastTimer;

  /// Double-tap seek feedback: where the tap landed (for zone detection) and
  /// the transient icon rendered AT the tap point so the seek is visible.
  Offset? _doubleTapPos;
  IconData? _seekFeedbackIcon;
  Offset? _seekFeedbackPos;
  Timer? _seekFeedbackTimer;

  /// Vertical-drag gesture (volume on the right half, brightness on the left,
  /// MX-Player style). Which side the drag started on and the value it began
  /// from, so the drag DELTA maps onto the existing value instead of
  /// overwriting it.
  VerticalDragSide? _dragSide;
  double _dragStartValue = 0;
  double _dragFeedbackValue = 0;

  /// Accumulated drag distance since [onVerticalDragStart] (px). The stream
  /// emits `details.delta` as the INCREMENT since the last update, so the
  /// value must be accumulated — a per-event `_dragStartValue - delta`
  /// formula made the slider jitter around the start value instead of
  /// following the finger (2026-08 bug report: "ada bug scroll").
  double _dragTotalDy = 0;

  /// Left half of the screen = brightness; right half = volume. Exposed for
  /// tests.
  VerticalDragSide _dragSideFor(Offset pos, double width) =>
      MpvControlsOverlay.dragSideFor(pos, width);

  void _onVerticalDragStart(DragStartDetails details) {
    final size = context.size;
    if (size == null) return;
    _dragSide = _dragSideFor(details.localPosition, size.width);
    _dragStartValue = _dragSide == VerticalDragSide.volume
        ? _volume
        : 100; // brightness starts at 100 (system) in this app's player
    _dragTotalDy = 0;
    _dragFeedbackValue = _dragStartValue;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final side = _dragSide;
    if (side == null) return;
    // Accumulate the incremental deltas, then map the TOTAL drag distance
    // onto the value — drag up = increase, drag down = decrease (~0.4 per
    // px, so a full-screen swipe sweeps the whole range).
    _dragTotalDy += details.delta.dy;
    final next =
        (_dragStartValue - _dragTotalDy * 0.4).clamp(0.0, 100.0).toDouble();
    _dragFeedbackValue = next;
    if (side == VerticalDragSide.volume) {
      _player.setVolume(next);
      if (next <= 0) {
        SettingsService.instance.setMuted(true);
      } else if (next > 0 && _muted) {
        SettingsService.instance.setMuted(false);
      }
    } else {
      // Brightness: 0..1 for the plugin.
      ScreenBrightness().setApplicationScreenBrightness(next / 100);
    }
    setState(() {});
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _dragSide = null;
  }

  /// Feedback pill for the vertical-drag gesture (shown at the drag side so
  /// the user sees the value change live).
  Widget? _buildDragFeedback(double width) {
    final side = _dragSide;
    if (side == null) return null;
    final icon = side == VerticalDragSide.volume
        ? Icons.volume_up_rounded
        : Icons.brightness_high_rounded;
    return Align(
      alignment: side == VerticalDragSide.volume
          ? const Alignment(0.8, 0)
          : const Alignment(-0.8, 0),
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              Text(
                '${_dragFeedbackValue.round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Subtitle state: a ValueNotifier so the modal settings sheet can update it
  // live while the (underlying) SubtitleViewConfiguration rebuilds.
  final ValueNotifier<bool> _subtitleVisible = ValueNotifier<bool>(true);
  final ValueNotifier<double> _subtitleSize = ValueNotifier<double>(32);

  List<VideoTrack> _videoTracks = const <VideoTrack>[];
  List<AudioTrack> _audioTracks = const <AudioTrack>[];
  List<SubtitleTrack> _subtitleTracks = const <SubtitleTrack>[];

  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    widget.notice?.addListener(_onNotice);
    _restorePreferences();
    _subscribe();
    _armHideTimer();
  }

  void _onNotice() {
    final message = widget.notice?.value;
    if (message != null && mounted) _showToast(message);
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapPos = details.localPosition;
  }

  /// Double-tap seek: left third of the screen rewinds [gestureSeekStep]
  /// (10s), right third forwards. Shows a brief icon AT the tap point
  /// (YouTube-style), cleared by [_seekFeedbackTimer].
  void _onDoubleTap() {
    final pos = _doubleTapPos;
    if (pos == null) return;
    final size = context.size;
    if (size == null) return;
    switch (MpvControlsOverlay.seekZoneFor(pos.dx, size.width)) {
      case SeekZone.left:
        _seekBy(-MpvControlsOverlay.gestureSeekStep);
        _showSeekFeedback(Icons.replay_10_rounded, pos);
      case SeekZone.right:
        _seekBy(MpvControlsOverlay.gestureSeekStep);
        _showSeekFeedback(Icons.forward_10_rounded, pos);
      case SeekZone.middle:
        break;
    }
  }

  void _showSeekFeedback(IconData icon, Offset pos) {
    _seekFeedbackTimer?.cancel();
    setState(() {
      _seekFeedbackIcon = icon;
      _seekFeedbackPos = pos;
    });
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _seekFeedbackIcon = null);
    });
  }

  /// Applies the persisted player preferences (playback speed, subtitle size,
  /// mute) to a freshly-created player session — so the user's choices from
  /// the last session are remembered on every new movie.
  void _restorePreferences() {
    final settings = SettingsService.instance;
    final savedRate = settings.playbackSpeed;
    _rate = savedRate;
    _player.setRate(savedRate);
    _subtitleSize.value = settings.subtitleSize
        .clamp(
          MpvControlsOverlay.minSubtitleSize,
          MpvControlsOverlay.maxSubtitleSize,
        )
        .toDouble();
    if (settings.muted) {
      _muted = true;
      _restoringMute = true;
      _player.setVolume(0);
    }
  }

  void _subscribe() {
    final s = _player.stream;
    _subs.add(s.playing.listen((v) {
      if (!mounted) return;
      setState(() => _playing = v);
      if (v) _armHideTimer();
    }));
    _subs.add(s.buffering.listen((v) {
      if (!mounted) return;
      setState(() => _buffering = v);
    }));
    _subs.add(s.position.listen((v) {
      if (!mounted || _dragging) return;
      // Throttle rebuilds: only update when a meaningful amount advanced.
      if ((v - _position).abs() >= const Duration(milliseconds: 200)) {
        setState(() => _position = v);
      } else {
        _position = v;
      }
    }));
    _subs.add(s.duration.listen((v) {
      if (!mounted) return;
      setState(() => _duration = v);
    }));
    _subs.add(s.volume.listen((v) {
      if (!mounted) return;
      setState(() {
        _volume = v;
        // While a restored mute is pending, ignore stale non-zero volume
        // events (the initial 100) — only the real mute (0) settles it.
        if (!_restoringMute || v <= 0) {
          _muted = v <= 0;
        }
        if (v <= 0) _restoringMute = false;
      });
    }));
    _subs.add(s.rate.listen((v) {
      if (!mounted) return;
      setState(() => _rate = v);
    }));
    _subs.add(s.tracks.listen((t) {
      if (!mounted) return;
      setState(() {
        _videoTracks = t.video;
        _audioTracks = t.audio;
        _subtitleTracks = t.subtitle;
      });
    }));
  }

  @override
  void dispose() {
    widget.notice?.removeListener(_onNotice);
    _hideTimer?.cancel();
    _toastTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    _subtitleVisible.dispose();
    _subtitleSize.dispose();
    super.dispose();
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _armHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleVisible() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _armHideTimer();
  }

  Future<void> _togglePlay() async {
    if (_player.state.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  /// Rewinds/forwards by [MpvControlsOverlay.seekStep] (5s), clamped to the
  /// playable range. The on-screen position updates instantly; libmpv catches
  /// up on its next position event.
  void _seekBy(Duration delta) {
    final target = MpvControlsOverlay.clampSeekTarget(
      _position,
      delta,
      _duration,
    );
    setState(() => _position = target);
    _player.seek(target);
    _armHideTimer();
  }

  void _toggleMute() {
    final nowMuted = !_muted;
    // Persist so the next session starts muted/unmuted as left.
    SettingsService.instance.setMuted(nowMuted);
    setState(() => _muted = nowMuted);
    if (nowMuted) {
      _lastVolume = _volume <= 0 ? 100 : _volume;
      _player.setVolume(0);
    } else {
      _player.setVolume(_lastVolume.clamp(20.0, 100.0));
    }
    _armHideTimer();
  }

  void _toggleSubtitles() {
    if (_subtitleTracks.isEmpty) {
      _armHideTimer();
      // 2026-08: streams without a subtitle track used to toggle nothing
      // visible (read as "broken"). Tell the user honestly. A transient
      // "tidak tersedia" during the first second of track enumeration is
      // a smaller sin than silence (a duration-based gate could swallow the
      // toast forever when mpv never reports a duration).
      _showToast('Subtitel tidak tersedia untuk stream ini.');
      return;
    }
    _subtitleVisible.value = !_subtitleVisible.value;
    // Explicitly select the FIRST track (not SubtitleTrack.auto()): libmpv's
    // `sid=auto` only enables DEFAULT/forced tracks, and HLS subtitle
    // variants are usually DEFAULT=NO — auto() would silently keep subtitles
    // off even after "Show subtitles".
    _player.setSubtitleTrack(
      _subtitleVisible.value && _subtitleTracks.isNotEmpty
          ? _subtitleTracks.first
          : SubtitleTrack.no(),
    );
    _armHideTimer();
  }

  void _onSliderChanged(double value) {
    setState(() {
      _dragging = true;
      _dragValue = value;
    });
  }

  void _onSliderEnd(double value) {
    final target = Duration(milliseconds: value.round());
    setState(() {
      _dragging = false;
      _position = target;
    });
    _player.seek(target);
    _armHideTimer();
  }

  double get _sliderValue {
    if (_dragging) return _dragValue;
    if (_duration <= Duration.zero) return 0;
    return _position.inMilliseconds
        .clamp(0, _duration.inMilliseconds)
        .toDouble();
  }

  Future<void> _openSettings() async {
    _hideTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16181D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SettingsSheet(
        player: _player,
        rate: _rate,
        subtitleSize: _subtitleSize,
        videoTracks: _videoTracks,
        audioTracks: _audioTracks,
        subtitleTracks: _subtitleTracks,
      ),
    );
    // Persist the subtitle size chosen in the sheet (the slider updates the
    // live ValueNotifier; the source of truth is saved once the sheet closes).
    SettingsService.instance.setSubtitleSize(_subtitleSize.value);
    // Re-arm auto-hide after the sheet closes (it was cancelled while open).
    if (mounted) _armHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // libmpv renders + letterboxes. Subtitles rendered by the framework
        // (external tracks) use the user-customizable size/visibility.
        ValueListenableBuilder<bool>(
          valueListenable: _subtitleVisible,
          builder: (context, visible, _) => ValueListenableBuilder<double>(
            valueListenable: _subtitleSize,
            builder: (context, size, _) => Video(
              controller: widget.controller,
              controls: NoVideoControls,
              subtitleViewConfiguration: SubtitleViewConfiguration(
                visible: visible,
                style: const TextStyle(
                  color: Colors.white,
                  height: 1.4,
                  backgroundColor: Color(0x88000000),
                  fontWeight: FontWeight.w600,
                ).copyWith(fontSize: size),
              ),
            ),
          ),
        ),
        // Tap layer: toggles controls on single tap; double-tap on the left
        // third rewinds 10s and the right third forwards 10s; vertical drag
        // on the right half changes volume, on the left half brightness
        // (MX-Player style). Sits UNDER the bars so button taps never reach it.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleVisible,
            onDoubleTapDown: _onDoubleTapDown,
            onDoubleTap: _onDoubleTap,
            onVerticalDragStart: _onVerticalDragStart,
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
          ),
        ),
        // Top bar (PiP, title, source, close X): ALWAYS visible so the
        // close button is always pressable — only the bottom controls
        // auto-hide (2026-08: hiding the X with the controls made it read
        // as broken). NOTE: the buffering spinner lives INSIDE the bottom
        // bar (replacing the play/pause icon) — nothing renders mid-screen
        // (2026-08: a centered spinner read as "controls in the middle").
        _buildTopBar(),
        // Bottom bar: play/pause, seek + time, mute, subtitles, settings.
        AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: _buildBottomBar(),
          ),
        ),
        // Brief toast (subtitle feedback etc.). Positioned in the UPPER area
        // (below the top bar), NEVER centered — a centered pill over the
        // middle of the video is exactly the "controls in the middle"
        // complaint (2026-08: the subtitle-unavailable toast read as a broken
        // overlay sitting on top of the movie).
        if (_toast != null)
          Align(
            alignment: const Alignment(0, -0.72),
            child: Material(
              color: const Color(0xE616181D),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  _toast!,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        // Double-tap seek feedback: a brief circular icon AT the tap point
        // (YouTube-style), auto-cleared by [_seekFeedbackTimer]. Transient
        // feedback, NOT a control — it never intercepts taps.
        if (_seekFeedbackIcon != null && _seekFeedbackPos != null)
          Positioned(
            left: _seekFeedbackPos!.dx - 30,
            top: _seekFeedbackPos!.dy - 30,
            child: IgnorePointer(
              child: Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _seekFeedbackIcon,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        // Vertical-drag feedback (volume right / brightness left) with the
        // live value — shown at the drag side, never centered.
        if (_dragSide != null) ...[
          _buildDragFeedback(context.size?.width ?? 0)!,
        ],
      ],
    );
  }

  Widget _buildTopBar() {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xCC000000), Color(0x00000000)],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 20),
        // NO SafeArea here (2026-08): this screen runs in IMMERSIVE mode
        // (system bars hidden), and on MIUI the padding reported after
        // toggling immersive can be a STALE/phantom bottom inset — a
        // SafeArea would push the bar up with it (the "controls in the
        // middle" complaint). The player's own padding handles the cutout.
        child: Row(
          children: [
            _RoundIconButton(
              icon: Icons.picture_in_picture_alt_rounded,
              tooltip: 'Pop up film (mini player)',
              onPressed: widget.onMinimize,
            ),
            if (widget.onTogglePortrait != null) ...[
              const SizedBox(width: 8),
              _RoundIconButton(
                icon: widget.portraitMode
                    ? Icons.fullscreen_rounded
                    : Icons.fullscreen_exit_rounded,
                tooltip: widget.portraitMode
                    ? 'Kembali ke fullscreen'
                    : 'Mode potret (seperti YouTube)',
                onPressed: widget.onTogglePortrait!,
                size: 30,
              ),
            ],
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.title,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                widget.sourceLabel,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
            const SizedBox(width: 10),
            _RoundIconButton(
              icon: Icons.close,
              tooltip: 'Close player',
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final time =
        '${formatDuration(_dragging ? Duration(milliseconds: _dragValue.round()) : _position)}'
        ' / ${formatDuration(_duration)}';
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xE6000000), Color(0x00000000)],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
        // NO SafeArea here (2026-08): in immersive mode the system bars are
        // hidden, so no bottom inset needs avoiding — and on MIUI the
        // reported bottom padding can be stale/phantom after toggling
        // immersive, which a SafeArea would translate into the bar floating
        // MID-SCREEN (the "controls in the middle" complaint). The bar
        // sticks to the real screen bottom, edge-to-edge.
        child: Row(
          children: [
            // ±5s seek buttons flank the play/pause button (standard layout).
            _RoundIconButton(
              icon: Icons.replay_5_rounded,
              tooltip: 'Mundur 5 detik',
              onPressed: () => _seekBy(-MpvControlsOverlay.seekStep),
              size: 34,
            ),
            if (_buffering)
              // Buffering spinner replaces the play/pause button — keeps
              // the UI honest (a spinner in the CENTER of the video read
              // as "controls in the middle", 2026-08) without hiding the
              // rest of the controls.
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white70,
                  ),
                ),
              )
            else
              _RoundIconButton(
                icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                tooltip: _playing ? 'Pause' : 'Play',
                onPressed: _togglePlay,
                size: 40,
              ),
            _RoundIconButton(
              icon: Icons.forward_5_rounded,
              tooltip: 'Maju 5 detik',
              onPressed: () => _seekBy(MpvControlsOverlay.seekStep),
              size: 34,
            ),
            Expanded(
              // CRITICAL (2026-08 root cause of the "controls in the
              // middle" complaint): `Expanded` lays out flex children with
              // TIGHT height = the Row's maxHeight — and because the bottom
              // bar's Align loosens height, that max is the FULL WINDOW. A
              // bare Slider therefore stretches to the whole window height →
              // the Row and the bar Container follow → the buttons get
              // vertically CENTERED = the control bar renders MID-SCREEN.
              // Bounding the cross-axis height keeps the Slider (and the
              // whole bottom bar) at its real ~48dp height, flush at the
              // bottom.
              child: SizedBox(
                height: 48,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: _sliderValue,
                    max: _duration.inMilliseconds > 0
                        ? _duration.inMilliseconds.toDouble()
                        : 1,
                    onChanged: _onSliderChanged,
                    onChangeEnd: _onSliderEnd,
                  ),
                ),
              ),
            ),
            Text(
              time,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (_rate != 1.0) ...[
              const SizedBox(width: 6),
              Text(
                '${_rate}x',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(width: 4),
            _RoundIconButton(
              icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              tooltip: _muted ? 'Unmute' : 'Mute',
              onPressed: _toggleMute,
              size: 34,
            ),
            _RoundIconButton(
              icon: _subtitleVisible.value
                  ? Icons.subtitles_rounded
                  : Icons.subtitles_off_rounded,
              tooltip:
                  _subtitleVisible.value ? 'Hide subtitles' : 'Show subtitles',
              onPressed: _toggleSubtitles,
              size: 34,
            ),
            _RoundIconButton(
              icon: Icons.settings_rounded,
              tooltip: 'Settings',
              onPressed: _openSettings,
              size: 34,
            ),
          ],
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
    this.size = 36,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: size * 0.62),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: size),
      ),
    );
  }
}

/// Modal bottom sheet with playback customization: speed, subtitle size,
/// video quality (resolution) and audio track.
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({
    required this.player,
    required this.rate,
    required this.subtitleSize,
    required this.videoTracks,
    required this.audioTracks,
    required this.subtitleTracks,
  });

  final Player player;
  final double rate;
  final ValueNotifier<double> subtitleSize;
  final List<VideoTrack> videoTracks;
  final List<AudioTrack> audioTracks;
  final List<SubtitleTrack> subtitleTracks;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  String _fmtTrackTitle(String? title, {String fallback = 'Track'}) {
    final t = title?.trim();
    if (t == null || t.isEmpty || t == 'Undetermined') return fallback;
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final videoTracks = widget.videoTracks;
    final audioTracks = widget.audioTracks;
    final subtitleTracks = widget.subtitleTracks;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const _SectionTitle('Kecepatan pemutaran'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final speed in MpvControlsOverlay.speedOptions)
                  ChoiceChip(
                    label: Text('${speed}x'),
                    selected: (widget.rate - speed).abs() < 0.001,
                    onSelected: (_) {
                      widget.player.setRate(speed);
                      SettingsService.instance.setPlaybackSpeed(speed);
                      Navigator.of(context).pop();
                    },
                    selectedColor: Colors.white,
                    backgroundColor: Colors.white10,
                    labelStyle: TextStyle(
                      color: (widget.rate - speed).abs() < 0.001
                          ? Colors.black
                          : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Ukuran subtitle'),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.text_fields, color: Colors.white54, size: 18),
                Expanded(
                  // Same Expanded cross-axis stretch as the player's seek
                  // bar (2026-08): bound the Slider's height so the Row (and
                  // the sheet content) keeps its real height.
                  child: SizedBox(
                    height: 48,
                    child: ValueListenableBuilder<double>(
                      valueListenable: widget.subtitleSize,
                      builder: (context, size, _) => Slider(
                        value: size,
                        min: MpvControlsOverlay.minSubtitleSize,
                        max: MpvControlsOverlay.maxSubtitleSize,
                        divisions: 8,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white30,
                        onChanged: (v) => widget.subtitleSize.value = v,
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: widget.subtitleSize,
                  builder: (context, size, _) => Text(
                    '${size.round()}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
            if (videoTracks.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _SectionTitle('Resolusi'),
              const SizedBox(height: 10),
              if (videoTracks.length > 1)
                // Multiple quality tracks — real choice.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final track in videoTracks)
                      _TrackChip(
                        label: _fmtTrackTitle(track.title, fallback: 'Auto'),
                        onTap: () {
                          widget.player.setVideoTrack(track);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                )
              else
                // Single track (the common HLS case): no tap-to-switch to
                // offer — just explain the stream is adaptive.
                const _SheetHint(
                  'Kualitas adaptif — dikelola otomatis oleh pemutar.',
                ),
            ],
            if (audioTracks.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _SectionTitle('Audio'),
              const SizedBox(height: 10),
              if (audioTracks.length > 1)
                // Multiple audio tracks — real choice.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final track in audioTracks)
                      _TrackChip(
                        label: _fmtTrackTitle(track.title, fallback: 'Default'),
                        onTap: () {
                          widget.player.setAudioTrack(track);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                )
              else
                // Single track — nothing to switch to.
                const _SheetHint('Menggunakan track audio default.'),
            ],
            const SizedBox(height: 20),
            const _SectionTitle('Track subtitle'),
            const SizedBox(height: 10),
            if (subtitleTracks.isEmpty)
              const _SheetHint('Subtitel tidak tersedia untuk stream ini.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TrackChip(
                    label: 'Off',
                    onTap: () {
                      widget.player.setSubtitleTrack(SubtitleTrack.no());
                      Navigator.of(context).pop();
                    },
                  ),
                  for (final track in subtitleTracks)
                    _TrackChip(
                      label: _fmtTrackTitle(track.title, fallback: 'Subtitel'),
                      onTap: () {
                        widget.player.setSubtitleTrack(track);
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _TrackChip extends StatelessWidget {
  const _TrackChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Colors.white10,
      labelStyle: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide.none,
    );
  }
}

class _SheetHint extends StatelessWidget {
  const _SheetHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: Colors.white38, fontSize: 12),
    );
  }
}

/// Horizontal third of the video surface a tap landed on. The double-tap
/// seek gesture maps [SeekZone.left] to rewind and [SeekZone.right] to
/// forward; the middle third does nothing.
enum SeekZone { left, middle, right }

/// Which half of the screen a vertical drag started on: right = volume,
/// left = brightness (MX-Player style).
enum VerticalDragSide { volume, brightness }
