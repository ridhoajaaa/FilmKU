import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/debouncer.dart';
import '../../domain/entities/movie.dart';
import '../providers/movie_providers.dart';
import '../widgets/error_view.dart';
import '../widgets/movie_card.dart';

/// Sort options for search results (2026-08 "Filter & urut pencarian").
enum SearchSort { popularity, rating, newest, titleAz }

/// Applies the optional [genreFilter] (TMDB genre ids), then [sort], to a
/// search result list. Search results carry `genreIds`/`voteAverage`/
/// `releaseDate`, so both are done client-side — no extra TMDB calls.
/// Exposed for tests.
@visibleForTesting
List<Movie> applySearchOrder(
  List<Movie> movies, {
  SearchSort sort = SearchSort.popularity,
  Set<int> genreFilter = const <int>{},
}) {
  var filtered = movies;
  if (genreFilter.isNotEmpty) {
    filtered =
        movies.where((m) => m.genreIds.any(genreFilter.contains)).toList();
  }
  switch (sort) {
    case SearchSort.popularity:
      return filtered;
    case SearchSort.rating:
      return [...filtered]
        ..sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
    case SearchSort.newest:
      return [...filtered]..sort((a, b) {
          final ad = a.releaseDate;
          final bd = b.releaseDate;
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });
    case SearchSort.titleAz:
      return [
        ...filtered
      ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }
}

/// Label for a [SearchSort] option (shown in the sort menu).
String searchSortLabel(SearchSort sort) {
  switch (sort) {
    case SearchSort.popularity:
      return 'Populer';
    case SearchSort.rating:
      return 'Rating tertinggi';
    case SearchSort.newest:
      return 'Terbaru';
    case SearchSort.titleAz:
      return 'Judul A–Z';
  }
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final Debouncer _debouncer =
      Debouncer(duration: const Duration(milliseconds: 450));

  /// Active sort of the results (client-side).
  SearchSort _sort = SearchSort.popularity;

  /// Active genre filter (TMDB genre ids; empty = all).
  final Set<int> _selectedGenres = <int>{};

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debouncer.run(() {
      if (mounted) {
        ref.read(searchQueryProvider.notifier).state = value;
      }
    });
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _sort = SearchSort.popularity;
      _selectedGenres.clear();
    });
    ref.read(searchQueryProvider.notifier).state = '';
  }

  void _toggleGenre(int id) {
    setState(() {
      if (!_selectedGenres.remove(id)) _selectedGenres.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);

    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    return Scaffold(
      appBar: AppBar(
        // iOS: REAL liquid-glass search field (shader-based GlassTextField).
        // Android: classic Material TextField.
        title: isIos
            ? GlassTextField(
                controller: _controller,
                onChanged: _onChanged,
                autofocus: true,
                placeholder: 'Search movies…',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.white54,
                ),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear_rounded,
                          color: Colors.white70,
                        ),
                        onPressed: _clear,
                      )
                    : null,
              )
            : TextField(
                controller: _controller,
                onChanged: _onChanged,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search movies…',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  border: InputBorder.none,
                  suffixIcon: query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear,
                              color: AppColors.textMuted),
                          onPressed: _clear,
                        )
                      : null,
                ),
              ),
        actions: [
          // Sort menu (client-side — see [applySearchOrder]).
          if (query.trim().isNotEmpty)
            PopupMenuButton<SearchSort>(
              icon: Icon(
                Icons.sort_rounded,
                color: _sort == SearchSort.popularity
                    ? AppColors.textMuted
                    : AppColors.accent,
              ),
              tooltip: 'Urutkan hasil',
              onSelected: (value) => setState(() => _sort = value),
              itemBuilder: (context) => [
                for (final s in SearchSort.values)
                  PopupMenuItem<SearchSort>(
                    value: s,
                    child: Row(
                      children: [
                        if (s == _sort)
                          const Icon(Icons.check_rounded,
                              size: 18, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Text(searchSortLabel(s)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: _buildBody(query, results),
    );
  }

  Widget _buildBody(String query, AsyncValue<List<Movie>> results) {
    if (query.trim().isEmpty) {
      return const _EmptyState();
    }
    return results.when(
      data: (movies) {
        final ordered = applySearchOrder(
          movies,
          sort: _sort,
          genreFilter: _selectedGenres,
        );
        if (ordered.isEmpty) {
          final isIos = Theme.of(context).platform == TargetPlatform.iOS;
          // iOS: REAL liquid-glass card (shader-based) for the empty state.
          final body = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off,
                  size: 56, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(
                _selectedGenres.isEmpty
                    ? 'No results for "$query"'
                    : 'No results for this genre filter',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          );
          return Center(
            child: isIos
                ? GlassContainer(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 28,
                    ),
                    child: body,
                  )
                : body,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Genre filter chips (only when there are results to filter).
            _GenreFilterBar(selected: _selectedGenres, onToggle: _toggleGenre),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.only(
                  // iOS: clear the floating glass capsule (extendBody content
                  // scrolls under the bar) so the last row is always reachable.
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: Theme.of(context).platform == TargetPlatform.iOS
                      ? 110
                      : 16,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.52,
                ),
                itemCount: ordered.length,
                itemBuilder: (context, index) =>
                    MovieCard(movie: ordered[index]),
              ),
            ),
          ],
        );
      },
      error: (error, stackTrace) => ErrorView(
        message: error.toString(),
        onRetry: () => ref.invalidate(searchResultsProvider),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    // iOS: REAL liquid-glass card (shader-based). Others: plain centered copy.
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return const Center(
        child: GlassContainer(
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 56, color: Colors.white38),
              SizedBox(height: 12),
              Text(
                'Search any movie',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Results appear as you type.',
                style: TextStyle(fontSize: 13, color: Colors.white38),
              ),
            ],
          ),
        ),
      );
    }
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search, size: 56, color: AppColors.textMuted),
          SizedBox(height: 12),
          Text(
            'Search any movie',
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
          SizedBox(height: 4),
          Text(
            'Results appear as you type.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Horizontal genre filter chips above the search grid — tap toggles a genre
/// filter (client-side; results already carry `genreIds`). "Semua" clears.
class _GenreFilterBar extends ConsumerWidget {
  const _GenreFilterBar({required this.selected, required this.onToggle});

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(genresProvider);
    return genres.maybeWhen(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final isIos = Theme.of(context).platform == TargetPlatform.iOS;
        return SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            children: [
              _FilterChip(
                label: 'Semua',
                selected: selected.isEmpty,
                isIos: isIos,
                onTap: () {
                  for (final id in [...selected]) {
                    onToggle(id); // toggle each off
                  }
                },
              ),
              for (final genre in list)
                _FilterChip(
                  label: genre.name,
                  selected: selected.contains(genre.id),
                  isIos: isIos,
                  onTap: () => onToggle(genre.id),
                ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.isIos,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isIos;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: isIos ? GlassContainer(child: chip) : chip,
    );
  }
}
