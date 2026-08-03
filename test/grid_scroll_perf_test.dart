import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:filmku/features/movies/domain/entities/movie.dart';
import 'package:filmku/features/movies/presentation/widgets/movie_card.dart';

/// Scroll-stress tests for the iOS glass movie grid.
///
/// 2026-08 (v1.3.2+): every MovieCard on iOS is now a shader-based
/// GlassContainer pinned to `GlassQuality.standard` + a keyed
/// RepaintBoundary. These tests prove the grid stays healthy under load:
///   1. GridView.builder stays LAZY — 60 movies must NOT build 60 cards at
///      once (eager building would be the real scroll killer).
///   2. Flinging to the bottom produces no exceptions / no layout overflows
///      (a widget-test failure is raised automatically otherwise), and
///      off-screen cards are recycled (card #0 leaves the tree).
void main() {
  final movies = List.generate(
    60,
    (i) => Movie(
      id: 1000 + i,
      title: 'Movie $i',
      overview: 'Overview $i',
      posterPath: '/poster$i.jpg',
      releaseDate: '2026-01-01',
      voteAverage: 7.0,
    ),
  );

  Future<void> pumpGrid(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GridView.builder(
              // Mirrors Search/Watchlist grids (3 columns, 0.52 aspect).
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                childAspectRatio: 0.52,
              ),
              itemCount: movies.length,
              itemBuilder: (context, index) => MovieCard(movie: movies[index]),
            ),
          ),
        ),
      );
      // Let the (placeholder) poster images settle.
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('iOS grid: cards are glass AND built lazily, not all 60 at once',
      (tester) async {
    await pumpGrid(tester);

    // Glass is really on in the grid context.
    expect(find.byType(GlassContainer), findsWidgets);
    expect(tester.takeException(), isNull);

    // Lazy: only the visible ~1 row of cards is in the tree.
    final built = tester.widgetList(find.byType(MovieCard)).length;
    expect(built, greaterThan(0));
    expect(built, lessThan(movies.length));
  });

  testWidgets(
      'iOS grid: scroll to bottom is clean — no overflow, cards recycle',
      (tester) async {
    await pumpGrid(tester);

    // Deterministically scroll all the way to the last row (fling physics
    // can settle early on a 10k-px grid).
    await tester.scrollUntilVisible(
      find.text('Movie 59'),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // No exception / RenderFlex overflow was raised during the scroll —
    // the framework fails the test automatically if any was.
    expect(tester.takeException(), isNull);

    // Recycling: card #0 left the tree after scrolling to the bottom.
    expect(find.text('Movie 0'), findsNothing);

    // And the grid still has content at the bottom.
    expect(find.byType(MovieCard), findsWidgets);
    expect(find.text('Movie 59'), findsOneWidget);
  });
}
