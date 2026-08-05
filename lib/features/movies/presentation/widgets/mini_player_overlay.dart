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

  /// Mini player window size (176 x 99, 16:9).
  static const double miniWidth = 176;
  static const double miniHeight = miniWidth * 9 / 16;

  /// Computes the mini player's top-left position from the current screen
  /// [size] and the user's [dragOffset] (relative to the bottom-right
  /// anchor). Pure — exposed for tests.
  ///
  /// 2026-08 (v1.3.17): the previous implementation wrapped the
  /// [Positioned] in a [LayoutBuilder] — ILLEGAL in Flutter (a ParentData
  /// widget must be a DIRECT child of the Stack; the pattern threw in debug
  /// and silently corrupted layout in release → the mini player rendered
  /// mid-screen and its video surface could cover the whole screen with a
  /// blank/white texture that ate every touch, forcing a force-quit). The
  /// anchor is now computed from [MediaQuery] size with the [Positioned]
  /// returned DIRECTLY from the overlay's build (a direct child of the
  /// app-level Stack) — bulletproof in every orientation.
  @visibleForTesting
  static Offset computeMiniPlayerPosition({
    required Size size,
    required Offset dragOffset,
    double width = miniWidth,
    double height = miniHeight,
    double margin = 12,
    double bottomGap = 120,
  }) {
    final baseLeft = size.width - width - margin;
    final baseTop = size.height - height - bottomGap;
    final maxLeft = (size.width - width).clamp(0.0, double.infinity).toDouble();
    final maxTop =
        (size.height - height).clamp(0.0, double.infinity).toDouble();
    final left = (baseLeft + dragOffset.dx).clamp(0.0, maxLeft);
    final top = (baseTop + dragOffset.dy).clamp(0.0, maxTop);
    return Offset(left, top);
  }

  @override
  State<MiniPlayerOverlay> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends State<MiniPlayerOverlay> {
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
      // Material one — so 800ms guarantees the popping screen's Video is
      // gone before this one attaches; two Video widgets sharing one
      // VideoController must never overlap).
      _revealTimer = Timer(const Duration(milliseconds: 800), () {
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

  Future<void> _expand() async {
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
      //
      // Wait for the END of the frame so the overlay's setState (fired by
      // expand() → _onServiceChanged) has REBUILT and unmounted the mini
      // player's Video BEFORE the fullscreen screen mounts its own Video on
      // the same controller — two Video widgets sharing one controller must
      // never exist in the same frame (texture theft → blank surface).
      await WidgetsBinding.instance.endOfFrame;
      // The session/screen may have been stopped or the overlay disposed
      // while waiting for the frame — don't push a dead route.
      if (!mounted || !MiniPlayerService.instance.isActive) return;
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
    // Direct [Positioned] — the overlay IS a direct child of the app-level
    // Stack, so the position data applies. (Wrapping it in a LayoutBuilder
    // made the Positioned a NON-direct child → ParentDataWidget corruption
    // in release → mid-screen/blank-surface bug, 2026-08.) MediaQuery size
    // registers a rebuild on rotation, so the bottom-right anchor follows
    // orientation.
    final size = MediaQuery.sizeOf(context);
    final pos = MiniPlayerOverlay.computeMiniPlayerPosition(
        size: size, dragOffset: _dragOffset);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final next = MiniPlayerOverlay.computeMiniPlayerPosition(
              size: size,
              dragOffset: _dragOffset + details.delta,
            );
            // Keep the offset relative to the bottom-right anchor: the
            // clamped position minus the anchor gives the new drag delta.
            _dragOffset = Offset(
              next.dx - (size.width - MiniPlayerOverlay.miniWidth - 12),
              next.dy - (size.height - MiniPlayerOverlay.miniHeight - 120),
            );
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
            width: MiniPlayerOverlay.miniWidth,
            height: MiniPlayerOverlay.miniHeight,
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
                  child: _PlayPauseButton(controller: session.videoController),
                ),
              ],
            ),
          ),
        ),
      ),
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
