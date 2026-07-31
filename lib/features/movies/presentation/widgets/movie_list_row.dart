import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/movie.dart';
import 'error_view.dart';
import 'movie_card.dart';

class MovieListRow extends ConsumerWidget {
  const MovieListRow({
    super.key,
    required this.title,
    required this.moviesAsync,
    this.onRetry,
  });

  final String title;
  final AsyncValue<List<Movie>> moviesAsync;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 215,
          child: moviesAsync.when(
            data: (movies) => movies.isEmpty
                ? const Center(
                    child: Text(
                      'No movies found',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: movies.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 10),
                    itemBuilder: (context, index) =>
                        MovieCard(movie: movies[index]),
                  ),
            error: (error, stackTrace) => ErrorView(
              message: error.toString(),
              onRetry: onRetry,
              compact: true,
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }
}
