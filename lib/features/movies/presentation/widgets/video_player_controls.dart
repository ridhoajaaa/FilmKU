import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';

/// Custom overlay controls for the native player: play/pause, ±10s skip,
/// draggable progress, time labels, a source picker entry and auto-hide.
class CustomVideoControls extends StatefulWidget {
  const CustomVideoControls({
    super.key,
    required this.controller,
    required this.title,
    this.onClose,
    this.onSelectSource,
    this.sourceLabel,
  });

  final VideoPlayerController controller;
  final String title;
  final VoidCallback? onClose;
  final VoidCallback? onSelectSource;
  final String? sourceLabel;

  @override
  State<CustomVideoControls> createState() => _CustomVideoControlsState();
}

class _CustomVideoControlsState extends State<CustomVideoControls> {
  bool _visible = true;
  Timer? _hideTimer;
  bool _dragging = false;
  double _dragValue = 0;

  /// Minimum interval between position-driven rebuilds. The video controller
  /// notifies at the playback frame rate while playing; the progress UI only
  /// needs a fraction of that, so throttling to ~4x/sec keeps the player
  /// smooth. Direct interactions (tap, skip, slider drag, reveal) still call
  /// setState immediately and are never throttled.
  static const Duration _rebuildThrottle = Duration(milliseconds: 250);

  DateTime _lastRebuild = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
    _resetTimer();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onUpdate() {
    // Only rebuild while the controls are visible (they auto-hide after a few
    // seconds of playback) and at most once per throttle window. Revealing
    // the controls calls setState via _showControls, so the UI never looks
    // stale.
    if (!mounted || !_visible) return;
    final now = DateTime.now();
    if (now.difference(_lastRebuild) < _rebuildThrottle) return;
    _lastRebuild = now;
    setState(() {});
  }

  void _resetTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.controller.value.isPlaying) {
        setState(() => _visible = false);
      }
    });
  }

  void _showControls() {
    setState(() => _visible = true);
    _resetTimer();
  }

  void _togglePlay() {
    final value = widget.controller.value;
    if (value.isPlaying) {
      widget.controller.pause();
    } else {
      widget.controller.play();
      _resetTimer();
    }
    setState(() {});
  }

  void _skip(Duration delta) {
    final current = widget.controller.value.position;
    final target = current + delta;
    widget.controller.seekTo(
      target < Duration.zero ? Duration.zero : target,
    );
    _showControls();
  }

  void _onSliderChanged(double value) {
    setState(() {
      _dragging = true;
      _dragValue = value;
    });
    _resetTimer();
  }

  void _onSliderEnd(double value) {
    final duration = widget.controller.value.duration;
    widget.controller.seekTo(
      Duration(milliseconds: (value * duration.inMilliseconds).round()),
    );
    setState(() => _dragging = false);
    _resetTimer();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final duration = value.duration;
    final position = value.position;

    final double progress = duration.inMilliseconds == 0
        ? 0
        : (position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();
    final shownProgress = _dragging ? _dragValue : progress;
    final shownPosition = Duration(
      milliseconds: (shownProgress * duration.inMilliseconds).round(),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _visible ? () => setState(() => _visible = false) : _showControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Scrims for legibility.
          AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                  stops: const [0.0, 0.25, 0.75, 1.0],
                ),
              ),
            ),
          ),

          // Buffering indicator.
          if (value.isBuffering && !_dragging)
            const Center(
              child: SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),

          if (_visible) ...[
            _TopBar(
              title: widget.title,
              sourceLabel: widget.sourceLabel,
              onClose: widget.onClose,
              onSelectSource: widget.onSelectSource,
            ),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ControlButton(
                    icon: Icons.replay_10,
                    tooltip: 'Back 10s',
                    onPressed: () => _skip(const Duration(seconds: -10)),
                  ),
                  const SizedBox(width: 18),
                  _ControlButton(
                    icon: value.isPlaying ? Icons.pause : Icons.play_arrow,
                    tooltip: value.isPlaying ? 'Pause' : 'Play',
                    iconSize: 62,
                    onPressed: _togglePlay,
                  ),
                  const SizedBox(width: 18),
                  _ControlButton(
                    icon: Icons.forward_10,
                    tooltip: 'Forward 10s',
                    onPressed: () => _skip(const Duration(seconds: 10)),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.accent,
                      inactiveTrackColor: AppColors.surfaceLight,
                      thumbColor: AppColors.accent,
                      overlayColor: AppColors.accent.withValues(alpha: 0.2),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: shownProgress.clamp(0.0, 1.0).toDouble(),
                      onChanged: _onSliderChanged,
                      onChangeEnd: _onSliderEnd,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          Formatters.formatDuration(shownPosition),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12.5,
                          ),
                        ),
                        Text(
                          Formatters.formatDuration(duration),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.sourceLabel,
    required this.onClose,
    required this.onSelectSource,
  });

  final String title;
  final String? sourceLabel;
  final VoidCallback? onClose;
  final VoidCallback? onSelectSource;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onClose,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onSelectSource != null && sourceLabel != null)
                GestureDetector(
                  onTap: onSelectSource,
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.surfaceLight),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.hd, size: 16, color: AppColors.star),
                        const SizedBox(width: 6),
                        Text(
                          sourceLabel!,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.onPressed,
    this.iconSize = 40,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      icon: Icon(icon, size: iconSize, color: Colors.white),
      onPressed: onPressed,
      splashRadius: 30,
      iconSize: iconSize,
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
