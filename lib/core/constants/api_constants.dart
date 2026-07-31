/// TMDB API endpoints and image URL builders used by the data layer.
class ApiConstants {
  ApiConstants._();

  static const String baseUrl = 'https://api.themoviedb.org/3';
  static const String imageBaseUrl = 'https://image.tmdb.org/t/p/';

  static const String trendingMovies = '/trending/movie/week';
  static const String popularMovies = '/movie/popular';
  static const String topRatedMovies = '/movie/top_rated';
  static const String upcomingMovies = '/movie/upcoming';
  static const String searchMovies = '/search/movie';
  static const String movieDetails = '/movie';
  static const String movieCredits = '/credits';
  static const String similarMovies = '/similar';

  static const String posterSize = 'w500';
  static const String backdropSize = 'w1280';
  static const String profileSize = 'w185';

  static const int apiTimeoutSeconds = 20;

  /// Builds an absolute image URL from a TMDB path (e.g. `/abc123.jpg`).
  static String image(String size, String? path) =>
      path == null ? '' : '$imageBaseUrl$size$path';
}
