/// App-wide constants shared across the whole application.
class AppConstants {
  AppConstants._();

  static const String appName = 'FilmKU';
  static const String tagline = 'Stream movies. Zero ads.';

  /// TMDB API key. A working default is embedded so the app runs out of the
  /// box; override it at build time via:
  /// `flutter run --dart-define=TMDB_API_KEY=your_key_here`
  /// or at runtime from Settings (stored in Hive, takes precedence).
  static const String tmdbApiKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: '497ddd1299fb3f83808649bbafa48d06',
  );

  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
}
