import 'package:filmku/core/local/watch_progress_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WatchProgress model', () {
    test('fraction maps position to 0..1', () {
      final p = WatchProgress(
        movieId: 1,
        title: 'X',
        position: const Duration(minutes: 30),
        duration: const Duration(minutes: 60),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(p.fraction, closeTo(0.5, 0.001));
    });

    test('fraction is 0 for zero/unknown duration', () {
      final p = WatchProgress(
        movieId: 1,
        title: 'X',
        position: const Duration(minutes: 30),
        duration: Duration.zero,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(p.fraction, 0);
    });

    test('toJson/fromJson round-trips', () {
      final p = WatchProgress(
        movieId: 42,
        title: 'Spider-Man',
        posterPath: '/abc.jpg',
        position: const Duration(minutes: 12, seconds: 30),
        duration: const Duration(hours: 2),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(WatchProgress.fromJson(p.toJson()).movieId, 42);
      expect(WatchProgress.fromJson(p.toJson()).title, 'Spider-Man');
      expect(WatchProgress.fromJson(p.toJson()).posterPath, '/abc.jpg');
      expect(
        WatchProgress.fromJson(p.toJson()).position,
        const Duration(minutes: 12, seconds: 30),
      );
      expect(
        WatchProgress.fromJson(p.toJson()).duration,
        const Duration(hours: 2),
      );
    });
  });

  group('WatchProgressService', () {
    test('is a singleton with a static init (no real Hive in unit tests)', () {
      // The service requires Hive.initFlutter + openBox — exercised in the
      // widget/integration layer. Here we only assert the API contract exists.
      expect(WatchProgressService.minSavePosition, const Duration(seconds: 15));
      expect(WatchProgressService.finishedFraction, closeTo(0.92, 0.001));
      expect(
        () => WatchProgressService.instance,
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
