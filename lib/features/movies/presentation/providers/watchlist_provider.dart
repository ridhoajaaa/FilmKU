import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/watchlist_service.dart';
import '../../domain/entities/movie.dart';

final watchlistServiceProvider = Provider<WatchlistService>(
  (ref) => WatchlistService.instance,
);

/// Holds the in-memory watchlist and persists every change to Hive.
class WatchlistNotifier extends StateNotifier<List<Movie>> {
  WatchlistNotifier(this._service) : super(_service.loadAll());

  final WatchlistService _service;

  bool contains(int id) => state.any((m) => m.id == id);

  Future<void> toggle(Movie movie) async {
    final exists = contains(movie.id);
    state = exists
        ? state.where((m) => m.id != movie.id).toList()
        : [...state, movie];
    await _service.saveAll(state);
  }

  void remove(int id) {
    state = state.where((m) => m.id != id).toList();
    _service.saveAll(state);
  }
}

final watchlistProvider = StateNotifierProvider<WatchlistNotifier, List<Movie>>(
  (ref) => WatchlistNotifier(ref.watch(watchlistServiceProvider)),
);
