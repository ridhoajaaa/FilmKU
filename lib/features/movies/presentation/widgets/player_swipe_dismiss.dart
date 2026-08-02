import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Wraps a fullscreen player with an iOS-style **swipe-down-to-dismiss**
/// gesture: drag the player down and release past the threshold (or fling
/// down) to leave fullscreen — no need to kill the app from the background.
///
/// On non-iOS platforms this is a no-op pass-through (Android users already
/// have the system back button), matching the platform-native behavior.
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
    // Android/iOS-only: Android already exits fullscreen with the system back
    // button; the swipe gesture is the iOS idiom the user asked for.
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return widget.child;
    }
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
