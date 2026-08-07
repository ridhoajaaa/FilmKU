import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/local/watch_history_service.dart';

final watchHistoryServiceProvider = Provider<WatchHistoryService>(
  (ref) => WatchHistoryService.instance,
);

/// Full watch history (newest first). Refreshed when a new play is recorded
/// (the mpv player records on first real playback; the screens refresh on
/// route return).
class WatchHistoryNotifier extends StateNotifier<List<WatchHistoryEntry>> {
  WatchHistoryNotifier(this._service) : super(_service.allEntries());

  final WatchHistoryService _service;

  void refresh() => state = _service.allEntries();
}

final watchHistoryProvider =
    StateNotifierProvider<WatchHistoryNotifier, List<WatchHistoryEntry>>(
  (ref) => WatchHistoryNotifier(ref.watch(watchHistoryServiceProvider)),
);
