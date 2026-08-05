import 'package:hive_flutter/hive_flutter.dart';

/// Persisted app settings backed by a Hive box. Safe to call from anywhere:
/// the box is opened before `runApp`, and every method reads the latest value.
class SettingsService {
  SettingsService._(this._box);

  static const String _boxName = 'settings';

  static const String keyApiKey = 'tmdb_api_key';
  static const String keyHeadless = 'headless_extraction';
  static const String keyFallbackWebview = 'fallback_webview';

  // Player preferences (2026-08): remembered across sessions so the mpv
  // player starts with the user's playback speed / subtitle size / mute.
  static const String keyPlaybackSpeed = 'player_playback_speed';
  static const String keySubtitleSize = 'player_subtitle_size';
  static const String keyMuted = 'player_muted';

  static SettingsService? _instance;

  static SettingsService get instance {
    assert(_instance != null, 'SettingsService.init() must be called first.');
    return _instance!;
  }

  final Box<dynamic> _box;

  static Future<SettingsService> init() async {
    final box = await Hive.openBox<dynamic>(_boxName);
    _instance = SettingsService._(box);
    return _instance!;
  }

  String get apiKey => (_box.get(keyApiKey) as String?) ?? '';
  Future<void> setApiKey(String value) => _box.put(keyApiKey, value.trim());

  bool get headlessExtraction => (_box.get(keyHeadless) as bool?) ?? true;
  Future<void> setHeadlessExtraction(bool value) =>
      _box.put(keyHeadless, value);

  bool get fallbackWebview => (_box.get(keyFallbackWebview) as bool?) ?? false;
  Future<void> setFallbackWebview(bool value) =>
      _box.put(keyFallbackWebview, value);

  /// Last playback speed used by the mpv player (default 1.0x).
  double get playbackSpeed =>
      (_box.get(keyPlaybackSpeed) as num?)?.toDouble() ?? 1.0;
  Future<void> setPlaybackSpeed(double value) =>
      _box.put(keyPlaybackSpeed, value);

  /// Last subtitle font size used by the mpv player (default 32px).
  double get subtitleSize =>
      (_box.get(keySubtitleSize) as num?)?.toDouble() ?? 32.0;
  Future<void> setSubtitleSize(double value) =>
      _box.put(keySubtitleSize, value);

  /// Whether the mpv player was muted when it was last closed.
  bool get muted => (_box.get(keyMuted) as bool?) ?? false;
  Future<void> setMuted(bool value) => _box.put(keyMuted, value);

  /// Per-source enable flag; sources are enabled by default.
  bool isSourceEnabled(String sourceId) =>
      (_box.get('source_$sourceId') as bool?) ?? true;
  Future<void> setSourceEnabled(String sourceId, bool value) =>
      _box.put('source_$sourceId', value);
}
