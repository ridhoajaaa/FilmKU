import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/features/movies/domain/entities/movie.dart';
import 'package:filmku/features/movies/presentation/widgets/hero_carousel.dart';

void main() {
  // Movies without backdrop paths so the cards render the local placeholder
  // (no network image loading inside tests).
  List<Movie> movies(int count) => List.generate(
        count,
        (i) => Movie(
          id: i,
          title: 'Movie $i',
          overview: '',
          posterPath: null,
          backdropPath: null,
        ),
      );

  /// The pause feature only matters while the carousel stays MOUNTED but is
  /// scrolled out of view. A ListView (sliver) unmounts off-cache children,
  /// so use a SingleChildScrollView + Column, which keeps every child
  /// mounted — exactly the scenario the autoplay pause addresses.
  Future<void> pumpApp(WidgetTester tester, List<Movie> items) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 250, child: HeroCarousel(movies: items)),
                // Tall spacer so the carousel can be scrolled out of view.
                const SizedBox(height: 1500),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double currentPage(WidgetTester tester) {
    final pageView = tester.widget<PageView>(find.byType(PageView));
    return pageView.controller!.page!;
  }

  /// Pumps one autoplay period (5s) plus the page animation (450ms) and
  /// expects the carousel to have advanced to [expectedPage].
  Future<void> expectAutoAdvance(
    WidgetTester tester,
    double expectedPage,
  ) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 600));
    expect(currentPage(tester), closeTo(expectedPage, 0.05));
  }

  testWidgets('auto-advances to the next page while visible', (tester) async {
    await pumpApp(tester, movies(4));
    await expectAutoAdvance(tester, 1.0);
  });

  testWidgets(
      'pauses autoplay when scrolled out of view and resumes when scrolled back',
      (tester) async {
    await pumpApp(tester, movies(4));

    // Sanity: while visible, the timer advances the carousel once.
    await expectAutoAdvance(tester, 1.0);

    // Scroll the carousel fully out of the viewport. The widget stays
    // mounted (SingleChildScrollView) — only its autoplay timer must stop.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();

    // Pump well past one autoplay period: the page must NOT change.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 600));
    expect(currentPage(tester), closeTo(1.0, 0.05));

    // Scroll back into view — autoplay resumes.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();

    await expectAutoAdvance(tester, 2.0);
  });

  testWidgets('renders nothing and never auto-advances with an empty list',
      (tester) async {
    await pumpApp(tester, movies(0));

    // No PageView is built for an empty list.
    expect(find.byType(PageView), findsNothing);

    // Pumping well past an autoplay period must not throw or change state.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a single movie and never auto-advances', (tester) async {
    await pumpApp(tester, movies(1));

    expect(find.byType(PageView), findsOneWidget);
    expect(currentPage(tester), closeTo(0.0, 0.01));

    // No autoplay timer exists for a single movie: the page must stay put.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 600));
    expect(currentPage(tester), closeTo(0.0, 0.01));
  });
}
