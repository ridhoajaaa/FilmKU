import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../data/datasources/stream_source_datasource.dart';
import '../../data/datasources/tmdb_remote_datasource.dart';
import '../../data/repositories/movie_repository_impl.dart';
import '../../domain/entities/genre.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/movie_details.dart';
import '../../domain/entities/video_source.dart';
import '../../domain/repositories/movie_repository.dart';

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------

final tmdbRemoteDataSourceProvider = Provider<TmdbRemoteDataSource>(
  (ref) => TmdbRemoteDataSource(ref.watch(apiClientProvider)),
);

final streamSourceDataSourceProvider = Provider<StreamSourceDataSource>(
  (ref) => StreamSourceDataSource(),
);

final movieRepositoryProvider = Provider<MovieRepository>(
  (ref) => MovieRepositoryImpl(
    tmdb: ref.watch(tmdbRemoteDataSourceProvider),
    streamSource: ref.watch(streamSourceDataSourceProvider),
  ),
);

// ---------------------------------------------------------------------------
// Home sections
// ---------------------------------------------------------------------------

final trendingMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref.watch(movieRepositoryProvider).getTrendingMovies(),
);

final popularMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref.watch(movieRepositoryProvider).getPopularMovies(),
);

final topRatedMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref.watch(movieRepositoryProvider).getTopRatedMovies(),
);

final upcomingMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref.watch(movieRepositoryProvider).getUpcomingMovies(),
);

// ---------------------------------------------------------------------------
// Detail & player
// ---------------------------------------------------------------------------

final movieDetailsProvider =
    FutureProvider.family<MovieDetails, int>((ref, id) {
  return ref.watch(movieRepositoryProvider).getMovieDetails(id);
});

final similarMoviesProvider =
    FutureProvider.family<List<Movie>, int>((ref, id) {
  return ref.watch(movieRepositoryProvider).getSimilarMovies(id);
});

// ---------------------------------------------------------------------------
// Genre browsing
// ---------------------------------------------------------------------------

final genresProvider = FutureProvider<List<Genre>>(
  (ref) => ref.watch(movieRepositoryProvider).getGenres(),
);

final genreMoviesProvider = FutureProvider.family<List<Movie>, int>((ref, id) {
  return ref.watch(movieRepositoryProvider).getMoviesByGenre(id);
});

final videoSourcesProvider =
    FutureProvider.family<List<VideoSource>, int>((ref, id) {
  return ref.watch(movieRepositoryProvider).getVideoSources(id);
});

// ---------------------------------------------------------------------------
// Search (debounced by the UI)
// ---------------------------------------------------------------------------

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<List<Movie>>((ref) {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return Future.value(const <Movie>[]);
  return ref.watch(movieRepositoryProvider).searchMovies(query);
});
