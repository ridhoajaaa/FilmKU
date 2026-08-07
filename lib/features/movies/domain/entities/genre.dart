import 'package:flutter/foundation.dart';

/// A movie genre (TMDB `/genre/movie/list`) used for genre browsing.
@immutable
class Genre {
  const Genre({required this.id, required this.name});

  final int id;
  final String name;
}
