import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/local/watch_progress_service.dart';

final watchProgressServiceProvider = Provider<WatchProgressService>(
  (ref) => WatchProgressService.instance,
);

/// Continue-watching entries (newest first). Refreshed by the screens that
/// mutate progress (the mpv player saves on close; the row refreshes on
/// route return) via [refresh].
class WatchProgressNotifier extends StateNotifier<List<WatchProgress>> {
  WatchProgressNotifier(this._service) : super(_service.all());

  final WatchProgressService _service;

  /// Reloads from the service (called when the player route pops).
  void refresh() => state = _service.all();

  Future<void> remove(int movieId) async {
    await _service.remove(movieId);
    refresh();
  }
}

final watchProgressProvider =
    StateNotifierProvider<WatchProgressNotifier, List<WatchProgress>>(
  (ref) => WatchProgressNotifier(ref.watch(watchProgressServiceProvider)),
);
