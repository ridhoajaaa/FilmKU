import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../providers/movie_providers.dart';
import '../widgets/error_view.dart';
import '../widgets/hero_carousel.dart';
import '../widgets/movie_list_row.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trending = ref.watch(trendingMoviesProvider);
    final popular = ref.watch(popularMoviesProvider);
    final topRated = ref.watch(topRatedMoviesProvider);
    final upcoming = ref.watch(upcomingMoviesProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => Future.wait([
            ref.refresh(trendingMoviesProvider.future),
            ref.refresh(popularMoviesProvider.future),
            ref.refresh(topRatedMoviesProvider.future),
            ref.refresh(upcomingMoviesProvider.future),
          ]),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const _HeaderBanner(),
              trending.when(
                data: (movies) => HeroCarousel(movies: movies),
                error: (error, stackTrace) => SizedBox(
                  height: 200,
                  child: ErrorView(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(trendingMoviesProvider),
                  ),
                ),
                loading: () => const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              MovieListRow(
                title: 'Popular',
                moviesAsync: popular,
                onRetry: () => ref.invalidate(popularMoviesProvider),
              ),
              MovieListRow(
                title: 'Top Rated',
                moviesAsync: topRated,
                onRetry: () => ref.invalidate(topRatedMoviesProvider),
              ),
              MovieListRow(
                title: 'Upcoming',
                moviesAsync: upcoming,
                onRetry: () => ref.invalidate(upcomingMoviesProvider),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          Icon(Icons.movie_filter, color: AppColors.accent, size: 30),
          SizedBox(width: 8),
          Text(
            'FilmKU',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          Spacer(),
          Text(
            'No Ads • No Popups',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
