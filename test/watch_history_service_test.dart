import 'package:filmku/core/local/watch_history_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WatchHistoryEntry model', () {
    test('toJson/fromJson round-trips', () {
      final entry = WatchHistoryEntry(
        movieId: 42,
        title: 'Spider-Man',
        posterPath: '/abc.jpg',
        watchedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final restored = WatchHistoryEntry.fromJson(entry.toJson());
      expect(restored.movieId, 42);
      expect(restored.title, 'Spider-Man');
      expect(restored.posterPath, '/abc.jpg');
      expect(restored.watchedAt.millisecondsSinceEpoch, 1700000000000);
    });

    test('fromJson tolerates missing fields (corrupted entries)', () {
      final restored = WatchHistoryEntry.fromJson(const {'movie_id': 7});
      expect(restored.movieId, 7);
      expect(restored.title, '');
      expect(restored.posterPath, isNull);
    });
  });

  group('WatchHistoryService', () {
    test('is a singleton with a static init (no real Hive in unit tests)', () {
      // The service requires Hive.initFlutter + openBox — exercised in the
      // widget/integration layer. Here we only assert the API contract exists.
      expect(WatchHistoryService.maxEntries, 200);
      expect(
        () => WatchHistoryService.instance,
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
