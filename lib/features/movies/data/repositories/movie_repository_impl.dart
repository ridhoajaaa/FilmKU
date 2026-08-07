import '../../domain/entities/genre.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/movie_details.dart';
import '../../domain/entities/video_source.dart';
import '../../domain/repositories/movie_repository.dart';
import '../datasources/stream_source_datasource.dart';
import '../datasources/tmdb_remote_datasource.dart';

/// Concrete [MovieRepository] that combines TMDB metadata with the
/// stream source aggregator.
class MovieRepositoryImpl implements MovieRepository {
  MovieRepositoryImpl({
    required TmdbRemoteDataSource tmdb,
    required StreamSourceDataSource streamSource,
  })  : _tmdb = tmdb,
        _streamSource = streamSource;

  final TmdbRemoteDataSource _tmdb;
  final StreamSourceDataSource _streamSource;

  static List<Movie> _toMovies(List<dynamic> models) =>
      models.map((e) => e as Movie).toList();

  @override
  Future<List<Movie>> getTrendingMovies() async =>
      _toMovies(await _tmdb.getTrendingMovies());

  @override
  Future<List<Movie>> getPopularMovies() async =>
      _toMovies(await _tmdb.getPopularMovies());

  @override
  Future<List<Movie>> getTopRatedMovies() async =>
      _toMovies(await _tmdb.getTopRatedMovies());

  @override
  Future<List<Movie>> getUpcomingMovies() async =>
      _toMovies(await _tmdb.getUpcomingMovies());

  @override
  Future<List<Movie>> searchMovies(String query) async =>
      _toMovies(await _tmdb.searchMovies(query));

  @override
  Future<MovieDetails> getMovieDetails(int id) async {
    final details = await _tmdb.getMovieDetails(id);
    final cast = await _tmdb.getCast(id);
    return details.withCast(cast);
  }

  @override
  Future<List<Movie>> getSimilarMovies(int id) async =>
      _toMovies(await _tmdb.getSimilarMovies(id));

  @override
  Future<List<Genre>> getGenres() => _tmdb.getGenres();

  @override
  Future<List<Movie>> getMoviesByGenre(int genreId) async =>
      _toMovies(await _tmdb.getMoviesByGenre(genreId));

  @override
  Future<List<VideoSource>> getVideoSources(int id) =>
      _streamSource.getMovieSources(id);
}
