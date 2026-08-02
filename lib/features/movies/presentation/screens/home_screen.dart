import 'dart:ui' show ImageFilter;

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
            // iOS: extra bottom padding clears the floating glass capsule
            // (extendBody content scrolls under it) so the last row is never
            // hidden behind the bar.
            padding: EdgeInsets.only(
              bottom:
                  Theme.of(context).platform == TargetPlatform.iOS ? 110 : 0,
            ),
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
    // iOS: liquid-glass header (blurred chip). Others: classic solid banner.
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0x14141424),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0x28FFFFFF)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.movie_filter,
                      color: Color(0xFF4DE1FF), size: 26),
                  SizedBox(width: 10),
                  Text(
                    'FilmKU',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Spacer(),
                  Text(
                    'No Ads • No Popups',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
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
