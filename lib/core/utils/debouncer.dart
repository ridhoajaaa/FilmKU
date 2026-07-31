import 'dart:async';

/// Simple debouncer used by the search screen to avoid spamming the API
/// while the user types.
class Debouncer {
  Debouncer({required this.duration});

  final Duration duration;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void dispose() => _timer?.cancel();
}
