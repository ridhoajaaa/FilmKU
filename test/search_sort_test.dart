import 'package:filmku/features/movies/domain/entities/movie.dart';
import 'package:filmku/features/movies/presentation/screens/search_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the search filter + sort (2026-08 \"Filter & urut
/// pencarian\"): [applySearchOrder] applies an optional genre filter then a
/// client-side sort to TMDB search results.
void main() {
  Movie movie({
    required int id,
    required String title,
    double rating = 5,
    String? releaseDate,
    List<int> genres = const <int>[],
  }) =>
      Movie(
        id: id,
        title: title,
        overview: '',
        releaseDate: releaseDate,
        voteAverage: rating,
        genreIds: genres,
      );

  final action = movie(
    id: 1,
    title: 'The Batman',
    rating: 8.1,
    releaseDate: '2022-03-04',
    genres: const [28, 80],
  );
  final comedy = movie(
    id: 2,
    title: 'Dune',
    rating: 8.0,
    releaseDate: '2021-10-22',
    genres: const [878, 12],
  );
  final old = movie(
    id: 3,
    title: 'Avatar',
    rating: 7.6,
    releaseDate: '2009-12-18',
    genres: const [878, 12, 28],
  );
  final list = [action, comedy, old];

  group('applySearchOrder genre filter', () {
    test('no filter keeps every movie', () {
      expect(applySearchOrder(list).length, 3);
    });

    test('filters by genre id', () {
      final filtered = applySearchOrder(list, genreFilter: const {878});
      expect(filtered.map((m) => m.id), containsAll([2, 3]));
      expect(filtered.any((m) => m.id == 1), isFalse);
    });

    test('empty result when no movie matches the filter', () {
      expect(
        applySearchOrder(list, genreFilter: const {99}),
        isEmpty,
      );
    });
  });

  group('applySearchOrder sort', () {
    test('popularity keeps the TMDB search order', () {
      expect(
        applySearchOrder(list, sort: SearchSort.popularity).map((m) => m.id),
        [1, 2, 3],
      );
    });

    test('rating sorts highest first', () {
      expect(
        applySearchOrder(list, sort: SearchSort.rating).map((m) => m.id),
        [1, 2, 3],
      );
    });

    test('newest sorts by release date, missing dates last', () {
      final withNull = [
        ...list,
        movie(id: 4, title: 'No Date', rating: 9),
      ];
      final ordered = applySearchOrder(withNull, sort: SearchSort.newest);
      expect(ordered.first.id, 1); // 2022
      expect(ordered.last.id, 4); // no date -> last
    });

    test('titleAz sorts alphabetically (case-insensitive)', () {
      final ordered = applySearchOrder(list, sort: SearchSort.titleAz);
      expect(ordered.map((m) => m.title), ['Avatar', 'Dune', 'The Batman']);
    });

    test('filter applies before sort', () {
      // Genre 28 = action: The Batman (1) + Avatar (3). A-Z order =>
      // Avatar (3) before The Batman (1); Dune (2) is filtered out.
      final ordered = applySearchOrder(
        list,
        sort: SearchSort.titleAz,
        genreFilter: const {28},
      );
      expect(ordered.map((m) => m.id), [3, 1]);
    });
  });

  group('searchSortLabel', () {
    test('labels every option', () {
      expect(searchSortLabel(SearchSort.popularity), 'Populer');
      expect(searchSortLabel(SearchSort.rating), 'Rating tertinggi');
      expect(searchSortLabel(SearchSort.newest), 'Terbaru');
      expect(searchSortLabel(SearchSort.titleAz), 'Judul A–Z');
    });
  });
}
