import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/movie_providers.dart';
import '../providers/settings_provider.dart';
import '../providers/watch_progress_provider.dart';
import '../widgets/continue_watching_row.dart';
import '../widgets/error_view.dart';
import '../widgets/hero_carousel.dart';
import '../widgets/movie_list_row.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the settings provider so the "API key missing" banner disappears
    // as soon as the user saves a key in Settings (Home stays alive in the
    // indexedStack — a plain SettingsService read would never rebuild it).
    final apiKeyFromSettings = ref.watch(settingsProvider).apiKey;
    final hasApiKey =
        apiKeyFromSettings.isNotEmpty || AppConstants.tmdbApiKey.isNotEmpty;
    final trending = ref.watch(trendingMoviesProvider);
    final popular = ref.watch(popularMoviesProvider);
    final topRated = ref.watch(topRatedMoviesProvider);
    final upcoming = ref.watch(upcomingMoviesProvider);
    // Continue-watching: refreshed when the player route pops (the mpv screen
    // saves progress on close) so the row reflects the latest position.
    final continueWatching = ref.watch(watchProgressProvider);

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
              // Blocking setup banner: without a TMDB API key no movie loads
              // at all. Give the user an unmissable, one-tap path to Settings
              // (2026-08 user report: "API key missing and Settings can't be
              // opened" — the tab bar was there, but the discovery path was
              // not). Rebuilds via the watched settingsProvider, so it
              // disappears the moment the key is saved.
              if (!hasApiKey)
                _ApiKeyBanner(
                  onOpenSettings: () => context.go('/settings'),
                ),
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
              // Resume where you left off — newest first.
              ContinueWatchingRow(entries: continueWatching),
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
    // iOS: REAL liquid-glass header (shader-based GlassContainer — replaces
    // the old hand-rolled BackdropFilter approximation). Others: classic
    // solid banner.
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: GlassContainer(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.movie_filter, color: Color(0xFFE8E8EA), size: 26),
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

/// Unmissable setup banner shown at the very top of Home when no TMDB API key
/// is configured. One tap jumps straight to the Settings tab where the key is
/// entered — no hunting through tabs (2026-08 user report: "API key missing
/// and Settings can't be opened").
class _ApiKeyBanner extends StatelessWidget {
  const _ApiKeyBanner({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    // iOS: REAL liquid-glass chip (shader-based GlassContainer) — replaces
    // the old hand-rolled frosted approximation, so the setup banner reads as
    // part of the same glass system as the header/tab bar. Android: solid
    // accent-tinted card.
    final content = isIos
        ? GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: _bannerRow(onOpenSettings),
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF3A2E0A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x66FFB02E)),
            ),
            child: _bannerRow(onOpenSettings),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: content,
    );
  }

  Widget _bannerRow(VoidCallback onOpenSettings) {
    return Row(
      children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB02E)),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TMDB API Key missing',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Add your key to load movies',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFFB02E),
            foregroundColor: const Color(0xFF1A1200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          onPressed: onOpenSettings,
          child: const Text('Add key'),
        ),
      ],
    );
  }
}
