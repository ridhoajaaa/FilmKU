import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/cast_member.dart';
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
}
