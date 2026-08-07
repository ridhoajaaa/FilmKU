import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/local/watch_progress_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../providers/watch_progress_provider.dart';

/// Horizontal "Lanjutkan menonton" row: movies the user started but didn't
/// finish, with a progress bar, tap to resume from where they left off.
class ContinueWatchingRow extends ConsumerWidget {
  const ContinueWatchingRow({super.key, required this.entries});

  final List<WatchProgress> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Theme.of(context).platform == TargetPlatform.iOS
              ? const GlassContainer(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    'Lanjutkan menonton',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                )
              : const Text(
                  'Lanjutkan menonton',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
        ),
        SizedBox(
          height: 165,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: entries.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _ContinueCard(
              entry: entries[index],
              onResumed: () =>
                  ref.read(watchProgressProvider.notifier).refresh(),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.entry, required this.onResumed});

  final WatchProgress entry;

  /// Called after the player route pops, so the row reflects the fresh
  /// position (or the entry is removed once the movie is finished).
  final VoidCallback onResumed;

  @override
  Widget build(BuildContext context) {
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    final card = SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _Backdrop(posterPath: entry.posterPath),
                ),
                // Progress bar over the bottom of the poster.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: entry.fraction,
                    minHeight: 3.5,
                    backgroundColor: Colors.black45,
                    color: AppColors.accent,
                  ),
                ),
                // Position pill (top-right) so the resume point is visible.
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      Formatters.formatDuration(entry.position),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                // Play glyph so it reads as "tap to resume".
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 40,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      onTap: () async {
        // ?resume=1 — the player resumes from this entry's saved position on
        // every playback path (direct extraction AND hidden auto-capture),
        // instead of starting from the beginning (2026-08 bug).
        await context.push('/player/${entry.movieId}?resume=1');
        onResumed();
      },
      child: isIos
          ? GlassContainer(
              // Same symmetric lighting as MovieCard so the whole Home grid
              // reads consistently centered (see movie_card.dart).
              settings: const LiquidGlassSettings(
                lightAngle: 1.5707963267948966, // π/2 — top light
                lightIntensity: 1.2,
                ambientRim: 0,
                specularSharpness: GlassSpecularSharpness.soft,
              ),
              padding: const EdgeInsets.all(8),
              child: card,
            )
          : card,
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.posterPath});

  final String? posterPath;

  @override
  Widget build(BuildContext context) {
    final path = posterPath;
    if (path == null) return _placeholder();
    return CachedNetworkImage(
      imageUrl: ApiConstants.image(ApiConstants.posterSize, path),
      fit: BoxFit.cover,
      placeholder: (context, url) => _placeholder(),
      errorWidget: (context, url, error) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        // Gradient instead of a flat dark slab: history entries saved before
        // the poster-fetch fix have a null posterPath, and a blank black box
        // read as broken. A subtle two-tone gradient makes the card look
        // intentional even without artwork.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2C2C30), Color(0xFF141416)],
          ),
        ),
        child: const Center(
          child:
              Icon(Icons.movie_outlined, color: AppColors.textMuted, size: 30),
        ),
      );
}
