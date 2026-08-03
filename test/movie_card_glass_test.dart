import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:filmku/features/movies/domain/entities/movie.dart';
import 'package:filmku/features/movies/presentation/widgets/movie_card.dart';

/// Widget tests for the iOS-only liquid-glass treatment on [MovieCard].
///
/// 2026-08: the movie grid/rows on iOS should read as one glass system — each
/// card wraps in a shader-based [GlassContainer]. Android must keep the
/// classic flat card untouched.
void main() {
  const movie = Movie(
    id: 155,
    title: 'The Dark Knight',
    overview: 'Batman faces the Joker.',
    posterPath: '/qJ2tW6WMUDux911r6m7haRef0WH.jpg',
    releaseDate: '2008-07-18',
    voteAverage: 8.5,
  );

  Future<void> pumpCard(WidgetTester tester, TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: MovieCard(movie: movie),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('iOS: MovieCard is wrapped in a GlassContainer', (tester) async {
    await pumpCard(tester, TargetPlatform.iOS);

    expect(tester.takeException(), isNull);
    expect(find.byType(GlassContainer), findsOneWidget);
    expect(find.text('The Dark Knight'), findsOneWidget);
  });

  testWidgets('iOS: card glass uses the scroll-safe standard quality',
      (tester) async {
    await pumpCard(tester, TargetPlatform.iOS);

    // Perf guard: cards live in grids/rows, so the glass MUST stay on the
    // lightweight shader tier (5-10x faster than BackdropFilter, safe while
    // scrolling). If a future inherited premium layer sneaks in, this fails.
    final glass = tester.widget<GlassContainer>(find.byType(GlassContainer));
    expect(glass.quality, GlassQuality.standard);
  });

  testWidgets('iOS: each glass card is isolated by a keyed RepaintBoundary',
      (tester) async {
    await pumpCard(tester, TargetPlatform.iOS);

    // Perf guard: the card's own keyed boundary must exist. (A plain
    // ancestor-finder would false-pass — MaterialApp/Scaffold internals add
    // their own RepaintBoundaries.) This pins the exact widget.
    expect(find.byKey(const ValueKey('glass-movie-card')), findsOneWidget);
  });

  testWidgets('Android: MovieCard stays a flat card (no glass)',
      (tester) async {
    await pumpCard(tester, TargetPlatform.android);

    expect(tester.takeException(), isNull);
    expect(find.byType(GlassContainer), findsNothing);
    expect(find.text('The Dark Knight'), findsOneWidget);
  });
}
