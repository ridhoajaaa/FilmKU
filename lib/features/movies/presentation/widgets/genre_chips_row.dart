import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../providers/movie_providers.dart';

/// Horizontal \"Jelajah per Genre\" chips row on Home: the main TMDB genres,
/// one tap opens the genre's movie grid. iOS renders each chip as a REAL
/// liquid-glass capsule; Android uses classic dark chips.
class GenreChipsRow extends ConsumerWidget {
  const GenreChipsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(genresProvider);
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;

    return genres.when(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        // Keep the row compact: the main browsing genres, skipping niche
        // filler like "Documentary"/"TV Movie" is fine — users still reach
        // them via search. First ~12 most popular genres cover the catalogue.
        const priority = <String>[
          'Action',
          'Adventure',
          'Animation',
          'Comedy',
          'Crime',
          'Drama',
          'Fantasy',
          'Horror',
          'Mystery',
          'Romance',
          'Science Fiction',
          'Thriller',
        ];
        final sorted = [...list]..sort((a, b) {
            final pa = priority.indexOf(a.name);
            final pb = priority.indexOf(b.name);
            if (pa == -1 && pb == -1) return a.name.compareTo(b.name);
            if (pa == -1) return 1;
            if (pb == -1) return -1;
            return pa.compareTo(pb);
          });
        final chips = sorted.take(12).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Text(
                'Jelajah per Genre',
                style: TextStyle(
                  fontSize: isIos ? 17 : 19,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: chips.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final genre = chips[index];
                  final chip = InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => context.push(
                      '/genre?id=${genre.id}&name=${Uri.encodeComponent(genre.name)}',
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text(
                        genre.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  );
                  return isIos
                      ? GlassContainer(child: chip)
                      : Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: chip,
                        );
                },
              ),
            ),
          ],
        );
      },
      error: (error, stackTrace) => const SizedBox.shrink(),
      loading: () => const SizedBox.shrink(),
    );
  }
}
