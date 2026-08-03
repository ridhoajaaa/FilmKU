import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/debouncer.dart';
import '../../domain/entities/movie.dart';
import '../providers/movie_providers.dart';
import '../widgets/error_view.dart';
import '../widgets/movie_card.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final Debouncer _debouncer =
      Debouncer(duration: const Duration(milliseconds: 450));

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
    ref.read(searchQueryProvider.notifier).state = '';
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
        if (movies.isEmpty) {
          final isIos = Theme.of(context).platform == TargetPlatform.iOS;
          // iOS: REAL liquid-glass card (shader-based) for the empty state.
          final body = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off,
                  size: 56, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(
                'No results for "$query"',
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
        return GridView.builder(
          padding: EdgeInsets.only(
            // iOS: clear the floating glass capsule (extendBody content
            // scrolls under the bar) so the last row is always reachable.
            left: 16,
            right: 16,
            top: 16,
            bottom: Theme.of(context).platform == TargetPlatform.iOS ? 110 : 16,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            childAspectRatio: 0.52,
          ),
          itemCount: movies.length,
          itemBuilder: (context, index) => MovieCard(movie: movies[index]),
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
