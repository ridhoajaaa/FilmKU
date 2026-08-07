import 'package:flutter/material.dart';

/// Wraps a fullscreen player with a **swipe-down-to-dismiss** gesture: drag
/// the player down and release past the threshold (or fling down) to leave
/// fullscreen — no need to kill the app from the background.
///
/// Active on EVERY platform (2026-08): the YouTube-style portrait flow needs
/// swipe-down-to-popup on Android too (the user tests on Android first), and
/// iOS users get the idiom they asked for. Android's system back button keeps
/// working as a second exit path.
///
/// While dragging, the player translates down with the finger; releasing
/// above the threshold springs it back. `HitTestBehavior.translucent` lets
/// taps and horizontal drags (seek bar, play/pause) pass through untouched.
class PlayerSwipeDismiss extends StatefulWidget {
  const PlayerSwipeDismiss({
    super.key,
    required this.onDismiss,
    required this.child,
  });

  /// Called once the downward drag passes [dismissThreshold] or the fling
  /// velocity exceeds [dismissVelocity].
  final VoidCallback onDismiss;

  final Widget child;

  /// Distance (logical px) the player must be dragged down before releasing
  /// dismisses it.
  static const double dismissThreshold = 140;

  /// Fling velocity (px/s) that dismisses regardless of drag distance.
  static const double dismissVelocity = 900;

  @override
  State<PlayerSwipeDismiss> createState() => _PlayerSwipeDismissState();
}

class _PlayerSwipeDismissState extends State<PlayerSwipeDismiss> {
  double _dragDy = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (details) {
        // Only follow downward drags; upward drags are ignored (no rubber
        // band above the top).
        if (details.delta.dy > 0) {
          setState(() {
            _dragDy = (_dragDy + details.delta.dy).clamp(0.0, 480.0);
          });
        }
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (_dragDy > PlayerSwipeDismiss.dismissThreshold ||
            velocity > PlayerSwipeDismiss.dismissVelocity) {
          widget.onDismiss();
        } else {
          setState(() => _dragDy = 0);
        }
      },
      onVerticalDragCancel: () => setState(() => _dragDy = 0),
      child: Transform.translate(
        offset: Offset(0, _dragDy),
        child: widget.child,
      ),
    );
  }
}
