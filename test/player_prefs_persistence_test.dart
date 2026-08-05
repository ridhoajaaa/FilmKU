import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:filmku/core/local/settings_service.dart';
import 'package:filmku/features/movies/presentation/widgets/mpv_controls_overlay.dart';

/// Player preferences (playback speed, subtitle size, mute) must survive app
/// restarts: they are persisted in the Hive-backed [SettingsService].
void main() {
  late Directory tmpDir;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('filmku_hive_player_prefs');
    Hive.init(tmpDir.path);
    await SettingsService.init();
  });

  tearDownAll(() async {
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {
      // best-effort cleanup
    }
  });

  test('defaults: 1.0x speed, 32px subtitle size, not muted', () {
    final s = SettingsService.instance;
    expect(s.playbackSpeed, 1.0);
    expect(s.subtitleSize, 32.0);
    expect(s.muted, isFalse);
  });

  test('playback speed round-trips', () async {
    final s = SettingsService.instance;
    for (final speed in MpvControlsOverlay.speedOptions) {
      await s.setPlaybackSpeed(speed);
      expect(s.playbackSpeed, speed);
    }
  });

  test('subtitle size round-trips (incl. bounds)', () async {
    final s = SettingsService.instance;
    await s.setSubtitleSize(MpvControlsOverlay.minSubtitleSize);
    expect(s.subtitleSize, MpvControlsOverlay.minSubtitleSize);
    await s.setSubtitleSize(MpvControlsOverlay.maxSubtitleSize);
    expect(s.subtitleSize, MpvControlsOverlay.maxSubtitleSize);
    await s.setSubtitleSize(44);
    expect(s.subtitleSize, 44.0);
  });

  test('muted round-trips', () async {
    final s = SettingsService.instance;
    await s.setMuted(true);
    expect(s.muted, isTrue);
    await s.setMuted(false);
    expect(s.muted, isFalse);
  });
}
