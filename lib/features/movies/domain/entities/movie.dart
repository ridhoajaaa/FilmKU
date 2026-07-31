import 'package:flutter/foundation.dart';

/// Core movie summary used across lists, cards, and the watchlist.
@immutable
class Movie {
  const Movie({
    required this.id,
    required this.title,
    required this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage = 0,
    this.genreIds = const <int>[],
  });

  final int id;
  final String title;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double voteAverage;
  final List<int> genreIds;

  /// Serialized to JSON so the watchlist can store it in Hive as plain text.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'overview': overview,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'release_date': releaseDate,
        'vote_average': voteAverage,
        'genre_ids': genreIds,
      };

  factory Movie.fromJson(Map<String, dynamic> json) => Movie(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: (json['title'] as String?) ?? '',
        overview: (json['overview'] as String?) ?? '',
        posterPath: json['poster_path'] as String?,
        backdropPath: json['backdrop_path'] as String?,
        releaseDate: json['release_date'] as String?,
        voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
        genreIds: (json['genre_ids'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const <int>[],
      );
}
