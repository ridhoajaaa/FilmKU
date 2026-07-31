import '../entities/movie.dart';
import '../entities/movie_details.dart';
import '../entities/video_source.dart';

/// Contract between the presentation and data layers.
abstract interface class MovieRepository {
  Future<List<Movie>> getTrendingMovies();
  Future<List<Movie>> getPopularMovies();
  Future<List<Movie>> getTopRatedMovies();
  Future<List<Movie>> getUpcomingMovies();
  Future<List<Movie>> searchMovies(String query);
  Future<MovieDetails> getMovieDetails(int id);
  Future<List<Movie>> getSimilarMovies(int id);

  /// Aggregates playable stream sources for [id] from every enabled provider.
  Future<List<VideoSource>> getVideoSources(int id);
}
