import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// One movie's saved playback progress (continue-watching entry).
class WatchProgress {
  const WatchProgress({
    required this.movieId,
    required this.title,
    this.posterPath,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final int movieId;
  final String title;
  final String? posterPath;

  /// Saved playback position (where to resume).
  final Duration position;

  /// Stream duration at save time (for the progress bar).
  final Duration duration;

  /// When the progress was last updated (newest first in the row).
  final DateTime updatedAt;

  /// Fraction 0..1 of the movie already watched (clamped, duration-safe).
  double get fraction {
    if (duration <= Duration.zero) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'movie_id': movieId,
        'title': title,
        'poster_path': posterPath,
        'position_ms': position.inMilliseconds,
        'duration_ms': duration.inMilliseconds,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory WatchProgress.fromJson(Map<String, dynamic> json) => WatchProgress(
        movieId: (json['movie_id'] as num?)?.toInt() ?? 0,
        title: (json['title'] as String?) ?? '',
        posterPath: json['poster_path'] as String?,
        position:
            Duration(milliseconds: (json['position_ms'] as num?)?.toInt() ?? 0),
        duration:
            Duration(milliseconds: (json['duration_ms'] as num?)?.toInt() ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['updated_at'] as num?)?.toInt() ?? 0,
        ),
      );
}

/// Persists per-movie playback progress in a Hive box (JSON strings, no
/// TypeAdapter needed) so the user can resume where they left off.
class WatchProgressService {
  WatchProgressService._(this._box);

  static const String _boxName = 'watch_progress';

  /// Progress under this is ignored (accidental opens / scrubbing start).
  static const Duration minSavePosition = Duration(seconds: 15);

  /// Progress past this means the movie was essentially finished — the entry
  /// is removed instead of listed as "continue watching".
  static const double finishedFraction = 0.92;

  static WatchProgressService? _instance;

  static WatchProgressService get instance {
    assert(
        _instance != null, 'WatchProgressService.init() must be called first.');
    return _instance!;
  }

  final Box<dynamic> _box;

  static Future<WatchProgressService> init() async {
    final box = await Hive.openBox<dynamic>(_boxName);
    _instance = WatchProgressService._(box);
    return _instance!;
  }

  static String _key(int movieId) => 'movie_$movieId';

  /// Saves [position]/[duration] for [movieId]. A position below
  /// [minSavePosition] is ignored; a position past [finishedFraction] clears
  /// the entry (the movie is done — not "continue watching" material).
  Future<void> save({
    required int movieId,
    required String title,
    String? posterPath,
    required Duration position,
    required Duration duration,
  }) async {
    if (position < minSavePosition) return;
    if (duration > Duration.zero &&
        position.inMilliseconds >=
            (duration.inMilliseconds * finishedFraction).round()) {
      await remove(movieId);
      return;
    }
    await _box.put(
      _key(movieId),
      jsonEncode(
        WatchProgress(
          movieId: movieId,
          title: title,
          posterPath: posterPath,
          position: position,
          duration: duration,
          updatedAt: DateTime.now(),
        ).toJson(),
      ),
    );
  }

  WatchProgress? get(int movieId) {
    final raw = _box.get(_key(movieId));
    if (raw is! String) return null;
    try {
      return WatchProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// All saved progress, newest first.
  List<WatchProgress> all() {
    final entries = <WatchProgress>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is! String) continue;
      try {
        entries.add(
            WatchProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // skip corrupted entries
      }
    }
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries;
  }

  Future<void> remove(int movieId) => _box.delete(_key(movieId));
}
