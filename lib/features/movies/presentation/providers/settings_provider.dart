import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/local/settings_service.dart';

final settingsServiceProvider = Provider<SettingsService>(
  (ref) => SettingsService.instance,
);

class SettingsState {
  const SettingsState({
    required this.apiKey,
    required this.headlessExtraction,
    required this.fallbackWebview,
    required this.browserHeaders,
  });

  final String apiKey;
  final bool headlessExtraction;
  final bool fallbackWebview;
  final bool browserHeaders;

  SettingsState copyWith({
    String? apiKey,
    bool? headlessExtraction,
    bool? fallbackWebview,
    bool? browserHeaders,
  }) =>
      SettingsState(
        apiKey: apiKey ?? this.apiKey,
        headlessExtraction: headlessExtraction ?? this.headlessExtraction,
        fallbackWebview: fallbackWebview ?? this.fallbackWebview,
        browserHeaders: browserHeaders ?? this.browserHeaders,
      );
}

/// Mirrors [SettingsService] into Riverpod state so the UI rebuilds on change.
class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier(this._service)
      : super(SettingsState(
          apiKey: _service.apiKey,
          headlessExtraction: _service.headlessExtraction,
          fallbackWebview: _service.fallbackWebview,
          browserHeaders: _service.browserHeaders,
        ));

  final SettingsService _service;

  void setApiKey(String value) {
    _service.setApiKey(value);
    state = state.copyWith(apiKey: value);
  }

  void setHeadlessExtraction(bool value) {
    _service.setHeadlessExtraction(value);
    state = state.copyWith(headlessExtraction: value);
  }

  void setFallbackWebview(bool value) {
    _service.setFallbackWebview(value);
    state = state.copyWith(fallbackWebview: value);
  }

  void setBrowserHeaders(bool value) {
    _service.setBrowserHeaders(value);
    state = state.copyWith(browserHeaders: value);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(ref.watch(settingsServiceProvider)),
);
