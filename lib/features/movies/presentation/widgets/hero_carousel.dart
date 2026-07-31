import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/movie.dart';

/// Auto-playing hero carousel for the Trending section.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.movies});

  final List<Movie> movies;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final PageController _controller =
      PageController(viewportFraction: 0.92, initialPage: 0);
  Timer? _timer;
  int _current = 0;

  /// Enclosing scrollable (HomeScreen's ListView), used to detect whether
  /// this carousel is currently on screen.
  ScrollableState? _scrollable;

  /// Mirrors the timer state so visibility transitions only act on changes
  /// (avoids resetting the 5s countdown on every scroll tick).
  bool _autoplayEnabled = true;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only register once — didChangeDependencies can re-fire on inherited
    // dependency changes and we must not add duplicate listeners.
    if (_scrollable == null) {
      _scrollable = Scrollable.of(context);
      _scrollable!.position.addListener(_onScrollChanged);
      // Check visibility once the first frame is laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateAutoplay());
    }
  }

  @override
  void dispose() {
    _scrollable?.position.removeListener(_onScrollChanged);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onScrollChanged() => _updateAutoplay();

  void _startAutoPlay() {
    _timer?.cancel();
    if (widget.movies.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      // Guard against the list shrinking below 2 items after the timer
      // started (otherwise `% widget.movies.length` could divide by zero).
      if (!mounted || widget.movies.length < 2) return;
      final next = (_current + 1) % widget.movies.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _stopAutoPlay() {
    _timer?.cancel();
    _timer = null;
  }

  /// True when any part of this carousel intersects the scroll viewport.
  bool get _isVisible {
    final box = context.findRenderObject() as RenderBox?;
    final scrollable = _scrollable;
    if (box == null || scrollable == null) return false;
    // The Scrollable's render object is the viewport (RenderViewport) itself.
    final viewport = scrollable.context.findRenderObject() as RenderBox?;
    if (viewport == null) return false;

    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    final itemTop = box.localToGlobal(Offset.zero).dy;
    final itemBottom = itemTop + box.size.height;

    return itemBottom > viewportTop && itemTop < viewportBottom;
  }

  /// Pauses autoplay while the carousel is scrolled out of view, and resumes
  /// it when it comes back on screen.
  void _updateAutoplay() {
    if (!mounted) return;
    final visible = _isVisible;
    if (visible && !_autoplayEnabled) {
      _autoplayEnabled = true;
      _startAutoPlay();
    } else if (!visible && _autoplayEnabled) {
      _autoplayEnabled = false;
      _stopAutoPlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.movies.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 250,
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.movies.length,
        onPageChanged: (index) {
          _current = index;
          if (_autoplayEnabled) _startAutoPlay();
        },
        itemBuilder: (context, index) => _HeroCard(movie: widget.movies[index]),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.movie});

  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final backdropPath = movie.backdropPath;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: GestureDetector(
        onTap: () => context.push('/movie/${movie.id}'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: backdropPath == null
                  ? _placeholder()
                  : CachedNetworkImage(
                      imageUrl: ApiConstants.image(
                          ApiConstants.backdropSize, backdropPath),
                      fit: BoxFit.cover,
                      placeholder: (context, url) => _placeholder(),
                      errorWidget: (context, url, error) => _placeholder(),
                    ),
            ),
            // Bottom gradient for readability.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          movie.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 6),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star,
                                size: 16, color: AppColors.star),
                            const SizedBox(width: 4),
                            Text(
                              Formatters.formatVote(movie.voteAverage),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              Formatters.formatDate(movie.releaseDate),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 26),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surface,
        child: const Center(
          child: Icon(Icons.movie, color: AppColors.textMuted, size: 44),
        ),
      );
}
