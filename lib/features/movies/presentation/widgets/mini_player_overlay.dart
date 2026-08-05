import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../core/media/mini_player_service.dart';
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

  Offset _position = Offset.zero;
  bool _positionInitialized = false;

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
      _positionInitialized = false;
      setState(() {
        _shown = false;
        _session = null;
      });
    }
  }

  Offset _defaultPosition(Size size) {
    return Offset(size.width - _width - 12, size.height - _height - 120);
  }

  void _expand() {
    final session = _session;
    if (session == null) return;
    MiniPlayerService.instance.expand();
    context.push(
      '/mpv-player',
      extra: MpvPlayerArgs(
        url: session.url,
        title: session.title,
        sourceLabel: session.sourceLabel,
        httpHeaders: session.httpHeaders,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null || !_shown) return const SizedBox.shrink();
    final size = MediaQuery.of(context).size;
    if (!_positionInitialized) {
      _position = _defaultPosition(size);
      _positionInitialized = true;
    }
    final dx = _position.dx.clamp(0.0, size.width - _width);
    final dy = _position.dy.clamp(0.0, size.height - _height);
    return Positioned(
      left: dx,
      top: dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx).clamp(0.0, size.width - _width),
              (_position.dy + details.delta.dy)
                  .clamp(0.0, size.height - _height),
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
          padding: const EdgeInsets.all(3),
          child: Icon(icon, color: Colors.white, size: 15),
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
