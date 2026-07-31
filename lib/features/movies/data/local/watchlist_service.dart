import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../domain/entities/movie.dart';

/// Persists the user's watchlist in a Hive box. Movies are stored as JSON
/// strings so no code-generated TypeAdapter is required.
class WatchlistService {
  WatchlistService._(this._box);

  static const String _boxName = 'watchlist';
  static const String _key = 'movies';

  static WatchlistService? _instance;

  static WatchlistService get instance {
    assert(_instance != null, 'WatchlistService.init() must be called first.');
    return _instance!;
  }

  final Box<dynamic> _box;

  static Future<WatchlistService> init() async {
    final box = await Hive.openBox<dynamic>(_boxName);
    _instance = WatchlistService._(box);
    return _instance!;
  }

  List<Movie> loadAll() {
    final raw = (_box.get(_key) as List<dynamic>?) ?? const <dynamic>[];
    final movies = <Movie>[];
    for (final entry in raw) {
      if (entry is String) {
        try {
          movies.add(Movie.fromJson(jsonDecode(entry) as Map<String, dynamic>));
        } catch (_) {
          // skip corrupted entries
        }
      }
    }
    return movies;
  }

  Future<void> saveAll(List<Movie> movies) {
    final raw = movies.map((m) => jsonEncode(m.toJson())).toList();
    return _box.put(_key, raw);
  }
}
