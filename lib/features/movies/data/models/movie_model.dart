import '../../domain/entities/movie.dart';

/// [Movie] with TMDB JSON parsing. Extends the entity so the domain layer
/// stays free of serialization concerns.
class MovieModel extends Movie {
  const MovieModel({
    required super.id,
    required super.title,
    required super.overview,
    super.posterPath,
    super.backdropPath,
    super.releaseDate,
    super.voteAverage,
    super.genreIds,
  });

  factory MovieModel.fromJson(Map<String, dynamic> json) => MovieModel(
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
