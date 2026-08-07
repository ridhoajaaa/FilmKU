import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/cast_member.dart';
import '../../domain/entities/genre.dart';
import '../models/cast_model.dart';
import '../models/movie_details_model.dart';
import '../models/movie_model.dart';

/// Remote data source for all TMDB metadata (movies, search, credits).
class TmdbRemoteDataSource {
  TmdbRemoteDataSource(this._client);

  final ApiClient _client;

  Future<List<MovieModel>> _fetchMovies(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final data = await _client.get(path, queryParameters: query);
    final results = (data as Map<String, dynamic>)['results'] as List<dynamic>?;
    return results == null
        ? const <MovieModel>[]
        : results
            .map((e) => MovieModel.fromJson(e as Map<String, dynamic>))
            .toList();
  }

  Future<List<MovieModel>> getTrendingMovies() =>
      _fetchMovies(ApiConstants.trendingMovies);

  Future<List<MovieModel>> getPopularMovies() =>
      _fetchMovies(ApiConstants.popularMovies);

  Future<List<MovieModel>> getTopRatedMovies() =>
      _fetchMovies(ApiConstants.topRatedMovies);

  Future<List<MovieModel>> getUpcomingMovies() =>
      _fetchMovies(ApiConstants.upcomingMovies);

  Future<List<MovieModel>> searchMovies(String query) => _fetchMovies(
        ApiConstants.searchMovies,
        query: {'query': query, 'include_adult': false},
      );

  Future<MovieDetailsModel> getMovieDetails(int id) async {
    final data = await _client.get('${ApiConstants.movieDetails}/$id');
    return MovieDetailsModel.fromJson(data as Map<String, dynamic>);
  }

  Future<List<CastMember>> getCast(int id) async {
    final data = await _client
        .get('${ApiConstants.movieDetails}/$id${ApiConstants.movieCredits}');
    final cast = (data as Map<String, dynamic>)['cast'] as List<dynamic>? ?? [];
    final members =
        cast.map((e) => CastModel.fromJson(e as Map<String, dynamic>)).toList();
    members.sort((a, b) => a.order.compareTo(b.order));
    return members.take(12).toList();
  }

  Future<List<MovieModel>> getSimilarMovies(int id) => _fetchMovies(
        '${ApiConstants.movieDetails}/$id${ApiConstants.similarMovies}',
      );

  /// All movie genres (TMDB `/genre/movie/list`).
  Future<List<Genre>> getGenres() async {
    final data = await _client.get('/genre/movie/list');
    final genres = (data as Map<String, dynamic>)['genres'] as List<dynamic>?;
    if (genres == null) return const <Genre>[];
    return genres
        .map((e) => Genre(
              id: ((e as Map<String, dynamic>)['id'] as num).toInt(),
              name: (e['name'] as String?) ?? '',
            ))
        .toList();
  }

  /// Popular movies of a single genre (TMDB `/discover/movie`).
  ///
  /// Fetches 3 pages (~60 movies) so a genre grid is actually worth browsing:
  /// the single-page default returned only ~20 titles and a genre screen read
  /// as "hanya sedikit film" (2026-08 user report). TMDB caps pages at 500
  /// but a genre rarely needs more than 60 hits to fill the grid.
  ///
  /// Deduped by id: `sort_by=popularity.desc` re-orders LIVE between the
  /// sequential page requests (popularity values drift), so page 1 and page 2
  /// can overlap — without a `seen` set the grid would show duplicate cards.
  Future<List<MovieModel>> getMoviesByGenre(int genreId) async {
    const totalPages = 3;
    final all = <MovieModel>[];
    final seen = <int>{};
    for (var page = 1; page <= totalPages; page++) {
      final data = await _client.get(
        '/discover/movie',
        queryParameters: {
          'with_genres': genreId,
          'sort_by': 'popularity.desc',
          'include_adult': false,
          'page': page,
        },
      );
      final results =
          (data as Map<String, dynamic>)['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) break; // no more pages for this genre
      for (final e in results) {
        final movie = MovieModel.fromJson(e as Map<String, dynamic>);
        if (seen.add(movie.id)) all.add(movie);
      }
    }
    return all;
  }
}
