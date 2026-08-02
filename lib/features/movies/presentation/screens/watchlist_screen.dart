import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/movie_card.dart';

class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movies = ref.watch(watchlistProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Watchlist')),
      body: movies.isEmpty
          ? const _EmptyWatchlist()
          : GridView.builder(
              padding: EdgeInsets.only(
                // iOS: clear the floating glass capsule (extendBody content
                // scrolls under the bar) so the last row is always reachable.
                left: 16,
                right: 16,
                top: 16,
                bottom:
                    Theme.of(context).platform == TargetPlatform.iOS
                        ? 110
                        : 16,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                childAspectRatio: 0.52,
              ),
              itemCount: movies.length,
              itemBuilder: (context, index) => MovieCard(movie: movies[index]),
            ),
    );
  }
}

class _EmptyWatchlist extends StatelessWidget {
  const _EmptyWatchlist();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border, size: 56, color: AppColors.textMuted),
          SizedBox(height: 12),
          Text(
            'Your watchlist is empty',
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
          SizedBox(height: 4),
          Text(
            'Tap the bookmark icon on any movie to save it here.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
