import '../../domain/entities/cast_member.dart';
import '../../domain/entities/movie_details.dart';
import 'movie_model.dart';

/// [MovieDetails] with TMDB JSON parsing. Cast is fetched separately via
/// `/credits` and merged in with [withCast].
class MovieDetailsModel extends MovieDetails {
  const MovieDetailsModel({
    required super.movie,
    super.tagline,
    super.runtime,
    super.voteCount,
    super.genres,
    super.cast,
  });

  factory MovieDetailsModel.fromJson(Map<String, dynamic> json) =>
      MovieDetailsModel(
        movie: MovieModel.fromJson(json),
        tagline: json['tagline'] as String?,
        runtime: (json['runtime'] as num?)?.toInt(),
        voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
        genres: (json['genres'] as List<dynamic>?)
                ?.map(
                    (g) => (g as Map<String, dynamic>)['name'] as String? ?? '')
                .where((name) => name.isNotEmpty)
                .toList() ??
            const <String>[],
      );

  MovieDetailsModel withCast(List<CastMember> cast) => MovieDetailsModel(
        movie: movie,
        tagline: tagline,
        runtime: runtime,
        voteCount: voteCount,
        genres: genres,
        cast: cast,
      );
}
