import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../providers/movie_providers.dart';
import '../widgets/error_view.dart';
import '../widgets/movie_card.dart';

/// Movies of one genre (TMDB `/discover/movie?with_genres=`), sorted by
/// popularity, with a shuffle button that opens a random pick from the list
/// (2026-08 "Jelajah per Genre" feature).
class GenreScreen extends ConsumerWidget {
  const GenreScreen({
    super.key,
    required this.genreId,
    required this.genreName,
  });

  final int genreId;
  final String genreName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movies = ref.watch(genreMoviesProvider(genreId));

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: Text(
          genreName,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        backgroundColor: AppColors.black,
        actions: [
          // Shuffle: open a random movie from this genre — for when the user
          // just wants to explore the genre without picking.
          movies.maybeWhen(
            data: (list) => list.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.shuffle_rounded,
                        color: AppColors.textPrimary),
                    tooltip: 'Acak film',
                    onPressed: () {
                      final pick = list[_randomIndex(list.length)];
                      context.push('/movie/${pick.id}');
                    },
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: movies.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Text(
                'No movies in this genre.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              childAspectRatio: 0.52,
            ),
            itemCount: list.length,
            itemBuilder: (context, index) => MovieCard(movie: list[index]),
          );
        },
        error: (error, stackTrace) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(genreMoviesProvider(genreId)),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  int _randomIndex(int length) =>
      DateTime.now().microsecondsSinceEpoch % length;
}
