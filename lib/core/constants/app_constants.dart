/// App-wide constants shared across the whole application.
class AppConstants {
  AppConstants._();

  static const String appName = 'FilmKU';
  static const String tagline = 'Stream movies. Zero ads.';

  /// App version shown in Settings → About. Keep in sync with `version:` in
  /// pubspec.yaml (bump BOTH on every update so users can tell which build
  /// they have installed).
  static const String appVersion = '1.3.32';

  /// TMDB API key. There is deliberately NO embedded default — you must
  /// provide your own key, either:
  ///   (a) at build time: `flutter run --dart-define=TMDB_API_KEY=your_key`
  ///   (b) at runtime: Settings → TMDB API Key (stored in Hive, takes
  ///       precedence, works without a rebuild).
  /// Without a key the movie metadata will not load — the app shows a clear
  /// "add your key in Settings" error instead of silently failing.
  static const String tmdbApiKey =
      String.fromEnvironment('TMDB_API_KEY', defaultValue: '');

  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
}
