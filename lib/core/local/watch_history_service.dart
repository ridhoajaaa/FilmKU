import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// One movie-play record in the full watch history (every play, including
/// finished movies — unlike [WatchProgressService] which only keeps
/// in-progress continue-watching entries).
class WatchHistoryEntry {
  const WatchHistoryEntry({
    required this.movieId,
    required this.title,
    this.posterPath,
    required this.watchedAt,
  });

  final int movieId;
  final String title;
  final String? posterPath;

  /// When the movie was last played (newest first).
  final DateTime watchedAt;

  Map<String, dynamic> toJson() => {
        'movie_id': movieId,
        'title': title,
        'poster_path': posterPath,
        'watched_at': watchedAt.millisecondsSinceEpoch,
      };

  factory WatchHistoryEntry.fromJson(Map<String, dynamic> json) =>
      WatchHistoryEntry(
        movieId: (json['movie_id'] as num?)?.toInt() ?? 0,
        title: (json['title'] as String?) ?? '',
        posterPath: json['poster_path'] as String?,
        watchedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['watched_at'] as num?)?.toInt() ?? 0,
        ),
      );
}

/// Full watch history in a Hive box (JSON strings, no TypeAdapter needed).
///
/// Separate from [WatchProgressService]: progress tracks where to RESUME;
/// history tracks what was WATCHED (for the Home "Riwayat tontonan" screen).
class WatchHistoryService {
  WatchHistoryService._(this._box);

  static const String _boxName = 'watch_history';

  /// Cap on stored entries (oldest are dropped beyond this).
  static const int maxEntries = 200;

  static WatchHistoryService? _instance;

  static WatchHistoryService get instance {
    assert(
        _instance != null, 'WatchHistoryService.init() must be called first.');
    return _instance!;
  }

  final Box<dynamic> _box;

  static Future<WatchHistoryService> init() async {
    final box = await Hive.openBox<dynamic>(_boxName);
    _instance = WatchHistoryService._(box);
    return _instance!;
  }

  static String _key(int movieId) => 'movie_$movieId';

  /// Records a play of [movieId]. Replaying a movie moves it to the TOP
  /// (watched again) instead of duplicating it.
  Future<void> record({
    required int movieId,
    required String title,
    String? posterPath,
  }) async {
    await _box.put(
      _key(movieId),
      jsonEncode(
        WatchHistoryEntry(
          movieId: movieId,
          title: title,
          posterPath: posterPath,
          watchedAt: DateTime.now(),
        ).toJson(),
      ),
    );
    final all = allEntries();
    if (all.length > maxEntries) {
      for (final old in all.skip(maxEntries)) {
        await _box.delete(_key(old.movieId));
      }
    }
  }

  /// All recorded plays, newest first.
  List<WatchHistoryEntry> allEntries() {
    final entries = <WatchHistoryEntry>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is! String) continue;
      try {
        entries.add(
          WatchHistoryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // skip corrupted entries
      }
    }
    entries.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    return entries;
  }

  Future<void> clear() => _box.clear();
}
