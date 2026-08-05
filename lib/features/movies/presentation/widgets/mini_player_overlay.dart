import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../core/media/mini_player_service.dart';
import '../../../../core/router/app_router.dart';
import '../screens/mpv_player_screen.dart';

/// Floating "pop up film" mini player.
///
/// Mounted in `app.dart` above the whole Navigator, so it stays visible on
/// every screen. When [MiniPlayerService] is minimized, a small draggable
/// window keeps playing the exact same session; tapping it expands back to
/// the fullscreen mpv player.
///
/// The reveal is DELAYED past the route-pop animation: the same
/// [VideoController] must never be rendered by two `Video` widgets at once
/// (the popping fullscreen screen would otherwise fight the mini window for
/// the texture).
class MiniPlayerOverlay extends StatefulWidget {
  const MiniPlayerOverlay({super.key});

  @override
  State<MiniPlayerOverlay> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends State<MiniPlayerOverlay> {
  static const double _width = 176;
  static const double _height = _width * 9 / 16;

  MiniPlayerSession? _session;
  bool _shown = false;
  Timer? _revealTimer;

  /// User drag delta relative to the bottom-right anchor, so the mini player
  /// stays anchored (follows rotation / screen-size changes) instead of
  /// freezing at a stale absolute position (2026-08: it appeared mid-screen
  /// because the anchor was computed once with the LANDSCAPE size of the
  /// fullscreen player, then portrait kicked in).
  Offset _dragOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    MiniPlayerService.instance.addListener(_onServiceChanged);
    _onServiceChanged();
  }

  @override
  void dispose() {
    MiniPlayerService.instance.removeListener(_onServiceChanged);
    _revealTimer?.cancel();
    super.dispose();
  }

  void _onServiceChanged() {
    final svc = MiniPlayerService.instance;
    if (svc.isMinimized && svc.session != null) {
      setState(() => _session = svc.session);
      _revealTimer?.cancel();
      // Wait out the route pop transition before attaching the texture here
      // (iOS uses a 500ms Cupertino transition — longer than the 300ms
      // Material one — so 600ms guarantees the popping screen's Video is
      // gone before this one attaches; two Video widgets sharing one
      // VideoController must never overlap).
      _revealTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted && MiniPlayerService.instance.isMinimized) {
          setState(() => _shown = true);
        }
      });
    } else {
      _revealTimer?.cancel();
      _dragOffset = Offset.zero;
      setState(() {
        _shown = false;
        _session = null;
      });
    }
  }

  void _expand() {
    final session = _session;
    if (session == null) return;
    MiniPlayerService.instance.expand();
    try {
      // The overlay lives ABOVE the Navigator (app builder), so a route push
      // must go through the global GoRouter — context.push would look the
      // router up from a context outside the navigator subtree and could
      // leave the session playing invisibly on failure (2026-08 on-device:
      // tapping the mini player hid it but the audio kept running until a
      // force-quit).
      appRouter.push(
        '/mpv-player',
        extra: MpvPlayerArgs(
          url: session.url,
          title: session.title,
          sourceLabel: session.sourceLabel,
          httpHeaders: session.httpHeaders,
        ),
      );
    } catch (_) {
      // Never leak a headless-playing session: stop it if navigation fails.
      MiniPlayerService.instance.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null || !_shown) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        // Bottom-right anchor (above the tab bar), computed from the STACK's
        // own constraints every build — the mini player is guaranteed to sit
        // at the bottom-right in any orientation and follows rotation,
        // instead of freezing at a position computed from a stale size
        // (2026-08: it appeared mid-screen because the size was captured
        // while the fullscreen player was still LANDSCAPE).
        final baseLeft = constraints.maxWidth - _width - 12;
        final baseTop = constraints.maxHeight - _height - 120;
        final maxLeft =
            (constraints.maxWidth - _width).clamp(0.0, double.infinity);
        final maxTop =
            (constraints.maxHeight - _height).clamp(0.0, double.infinity);
        final left = (baseLeft + _dragOffset.dx).clamp(0.0, maxLeft);
        final top = (baseTop + _dragOffset.dy).clamp(0.0, maxTop);
        return Positioned(
          left: left,
          top: top,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                final nextLeft = (baseLeft + _dragOffset.dx + details.delta.dx)
                    .clamp(0.0, maxLeft);
                final nextTop = (baseTop + _dragOffset.dy + details.delta.dy)
                    .clamp(0.0, maxTop);
                _dragOffset = Offset(nextLeft - baseLeft, nextTop - baseTop);
              });
            },
            onTap: _expand,
            child: Material(
              color: Colors.black,
              elevation: 10,
              shadowColor: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: _width,
                height: _height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Video(
                      controller: session.videoController,
                      controls: NoVideoControls,
                      wakelock: false,
                    ),
                    // Subtle scrim so the floating controls read on bright frames.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x33000000), Color(0x66000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: _MiniButton(
                        icon: Icons.close,
                        tooltip: 'Stop playback',
                        onPressed: () => MiniPlayerService.instance.stop(),
                      ),
                    ),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child:
                          _PlayPauseButton(controller: session.videoController),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
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
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatefulWidget {
  const _PlayPauseButton({required this.controller});

  final VideoController controller;

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton> {
  late final StreamSubscription<bool> _playingSub;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _playing = widget.controller.player.state.playing;
    _playingSub = widget.controller.player.stream.playing.listen((v) {
      if (mounted) setState(() => _playing = v);
    });
  }

  @override
  void dispose() {
    _playingSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MiniButton(
      icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
      tooltip: _playing ? 'Pause' : 'Play',
      onPressed: () async {
        if (_playing) {
          await widget.controller.player.pause();
        } else {
          await widget.controller.player.play();
        }
      },
    );
  }
}
