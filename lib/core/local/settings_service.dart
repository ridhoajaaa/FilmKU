import 'package:hive_flutter/hive_flutter.dart';

/// Persisted app settings backed by a Hive box. Safe to call from anywhere:
/// the box is opened before `runApp`, and every method reads the latest value.
class SettingsService {
  SettingsService._(this._box);

  static const String _boxName = 'settings';

  static const String keyApiKey = 'tmdb_api_key';
  static const String keyHeadless = 'headless_extraction';
  static const String keyFallbackWebview = 'fallback_webview';

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

  /// Per-source enable flag; sources are enabled by default.
  bool isSourceEnabled(String sourceId) =>
      (_box.get('source_$sourceId') as bool?) ?? true;
  Future<void> setSourceEnabled(String sourceId, bool value) =>
      _box.put('source_$sourceId', value);
}
