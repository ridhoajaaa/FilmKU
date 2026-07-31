import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/cast_member.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/movie_details.dart';
import '../providers/movie_providers.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/error_view.dart';
import '../widgets/movie_list_row.dart';

class DetailScreen extends ConsumerWidget {
  const DetailScreen({super.key, required this.movieId});

  final int movieId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(movieDetailsProvider(movieId));
    final similar = ref.watch(similarMoviesProvider(movieId));
    final isSaved = ref.watch(watchlistProvider).any((m) => m.id == movieId);

    return Scaffold(
      body: details.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(movieDetailsProvider(movieId)),
        ),
        data: (data) => _DetailContent(
          details: data,
          similar: similar,
          isSaved: isSaved,
          onPlay: () => context.push('/player/$movieId'),
          onToggleWatchlist: () =>
              ref.read(watchlistProvider.notifier).toggle(data.movie),
        ),
      ),
    );
  }
}

class _DetailContent extends ConsumerWidget {
  const _DetailContent({
    required this.details,
    required this.similar,
    required this.isSaved,
    required this.onPlay,
    required this.onToggleWatchlist,
  });

  final MovieDetails details;
  final AsyncValue<List<Movie>> similar;
  final bool isSaved;
  final VoidCallback onPlay;
  final VoidCallback onToggleWatchlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movie = details.movie;
    final backdropPath = movie.backdropPath;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 280,
          pinned: true,
          backgroundColor: AppColors.black,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (backdropPath != null)
                  CachedNetworkImage(
                    imageUrl: ApiConstants.image(
                        ApiConstants.backdropSize, backdropPath),
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: AppColors.surface,
                    ),
                    errorWidget: (context, url, error) =>
                        Container(color: AppColors.surface),
                  )
                else
                  Container(color: AppColors.surface),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.black.withValues(alpha: 0.9),
                      ],
                      stops: const [0.4, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TitleBlock(details: details),
                const SizedBox(height: 14),
                _ActionRow(
                  isSaved: isSaved,
                  onPlay: onPlay,
                  onToggleWatchlist: onToggleWatchlist,
                ),
                if ((details.genres).isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: details.genres
                        .map((genre) => Chip(
                              label: Text(genre),
                              backgroundColor: AppColors.surfaceLight,
                              side: BorderSide.none,
                              labelStyle: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ))
                        .toList(),
                  ),
                ],
                if (details.tagline != null && details.tagline!.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    details.tagline!,
                    style: const TextStyle(
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  movie.overview.isEmpty
                      ? 'No synopsis available.'
                      : movie.overview,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (details.cast.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Top Cast',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CastRow(cast: details.cast),
                ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: MovieListRow(
            title: 'Similar Movies',
            moviesAsync: similar,
            onRetry: () => ref.invalidate(similarMoviesProvider(movie.id)),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.details});

  final MovieDetails details;

  @override
  Widget build(BuildContext context) {
    final movie = details.movie;
    final year = Formatters.formatDate(movie.releaseDate);
    final runtime = Formatters.formatRuntime(details.runtime);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 110,
            height: 160,
            child: movie.posterPath == null
                ? Container(
                    color: AppColors.surface,
                    child: const Center(
                      child: Icon(Icons.movie_outlined,
                          color: AppColors.textMuted),
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: ApiConstants.image(
                        ApiConstants.posterSize, movie.posterPath!),
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: AppColors.surface,
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.surface,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                movie.title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$year • $runtime',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.star, size: 18, color: AppColors.star),
                  const SizedBox(width: 5),
                  Text(
                    Formatters.formatVote(movie.voteAverage),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${details.voteCount} votes)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.isSaved,
    required this.onPlay,
    required this.onToggleWatchlist,
  });

  final bool isSaved;
  final VoidCallback onPlay;
  final VoidCallback onToggleWatchlist;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onToggleWatchlist,
            icon: Icon(
              isSaved ? Icons.bookmark : Icons.bookmark_outline,
              size: 20,
            ),
            label: Text(isSaved ? 'Saved' : 'Save'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.surfaceLight),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _CastRow extends StatelessWidget {
  const _CastRow({required this.cast});

  final List<CastMember> cast;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cast.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final member = cast[index];
          return SizedBox(
            width: 90,
            child: Column(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 74,
                    height: 74,
                    child: member.profilePath == null
                        ? Container(
                            color: AppColors.surfaceLight,
                            child: const Icon(Icons.person,
                                color: AppColors.textMuted),
                          )
                        : CachedNetworkImage(
                            imageUrl: ApiConstants.image(
                                ApiConstants.profileSize, member.profilePath!),
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: AppColors.surfaceLight,
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: AppColors.surfaceLight,
                              child: const Icon(Icons.person,
                                  color: AppColors.textMuted),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  member.character,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
