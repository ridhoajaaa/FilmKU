import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/movie.dart';

class MovieCard extends StatelessWidget {
  const MovieCard({super.key, required this.movie, this.width = 120});

  final Movie movie;
  final double width;

  @override
  Widget build(BuildContext context) {
    // iOS: the whole card sits in a REAL liquid-glass panel (shader-based
    // GlassContainer) — the frosted rim shows around the poster and behind
    // the title/rating, so Home rows, Search/Watchlist grids read as one
    // glass system. Android keeps the classic flat card.
    final card = SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _Poster(movie: movie),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            movie.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(Icons.star, size: 14, color: AppColors.star),
              const SizedBox(width: 4),
              Text(
                Formatters.formatVote(movie.voteAverage),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return GestureDetector(
      onTap: () => context.push('/movie/${movie.id}'),
      child: Theme.of(context).platform == TargetPlatform.iOS
          ? RepaintBoundary(
              // Defense-in-depth on top of the delegate's per-item boundary:
              // this keyed boundary keeps each card's glass layer isolated, so
              // a neighbour's image load / hero animation repaints only this
              // card. Cheap — a layer is only allocated when it repaints.
              key: const ValueKey('glass-movie-card'),
              child: GlassContainer(
                // Explicitly pin the lightweight scroll-safe shader tier.
                // Widget-level quality wins over any inherited premium layer,
                // so cards in grids/rows stay cheap even if a future screen
                // (or GlassScaffold) promotes the ambient quality.
                quality: GlassQuality.standard,
                // Symmetric lighting for poster cards (2026-08 user report:
                // "poster di dalam kartu kelihatan geser ke kiri"). The
                // package's default key light (0.75π = 135°, upper-left)
                // paints a directional rim/specular highlight that makes the
                // glass frame around a poster read heavier on one side — the
                // layout itself is pixel-centered, so this was purely the
                // lighting illusion. Straight-down light (π/2) keeps the
                // frosted look but lights both edges identically.
                settings: const LiquidGlassSettings(
                  lightAngle: 1.5707963267948966, // π/2 — top light
                  lightIntensity: 1.2, // calmer than the default 2.0
                  ambientRim: 0,
                  specularSharpness: GlassSpecularSharpness.soft,
                ),
                // Thin padding keeps the frosted rim subtle — the poster still
                // dominates the card. The grid/list parents give tight
                // constraints, so the inner Column just shrinks slightly.
                padding: const EdgeInsets.all(8),
                child: card,
              ),
            )
          : card,
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.movie});

  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final posterPath = movie.posterPath;
    if (posterPath == null) return _placeholder();

    return CachedNetworkImage(
      imageUrl: ApiConstants.image(ApiConstants.posterSize, posterPath),
      fit: BoxFit.cover,
      placeholder: (context, url) => _placeholder(),
      errorWidget: (context, url, error) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surface,
        child: const Center(
          child: Icon(Icons.movie_outlined, color: AppColors.textMuted),
        ),
      );
}
