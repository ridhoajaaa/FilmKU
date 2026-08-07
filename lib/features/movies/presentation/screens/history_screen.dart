import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/local/watch_history_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../providers/watch_history_provider.dart';

/// Full watch history: every movie the user has played, newest first — the
/// complement of the Home "Lanjutkan menonton" row (which only lists
/// in-progress movies).
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(watchHistoryProvider);
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: Text(
          'Riwayat tontonan',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: isIos ? 17 : 20,
          ),
        ),
        backgroundColor: AppColors.black,
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded,
                  color: AppColors.textMuted),
              tooltip: 'Clear history',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: const Text(
                      'Hapus semua riwayat?',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                    content: const Text(
                      'Daftar riwayat tontonan akan dikosongkan.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => context.pop(false),
                        child: const Text('Batal'),
                      ),
                      TextButton(
                        onPressed: () => context.pop(true),
                        child: const Text('Hapus'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await WatchHistoryService.instance.clear();
                  if (context.mounted) {
                    ref.read(watchHistoryProvider.notifier).refresh();
                  }
                }
              },
            ),
        ],
      ),
      body: entries.isEmpty
          ? _EmptyHistory(isIos: isIos)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _HistoryTile(entry: entries[index]),
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final WatchHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    final tile = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/movie/${entry.movieId}'),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 74,
              child: entry.posterPath == null
                  ? Container(
                      color: AppColors.surfaceLight,
                      child: const Icon(Icons.movie_outlined,
                          color: AppColors.textMuted),
                    )
                  : CachedNetworkImage(
                      imageUrl: ApiConstants.image(
                          ApiConstants.posterSize, entry.posterPath!),
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Container(color: AppColors.surfaceLight),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.surfaceLight,
                        child: const Icon(Icons.movie_outlined,
                            color: AppColors.textMuted),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _dateLabel(entry.watchedAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
    return isIos
        ? GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: tile,
          )
        : Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: tile,
          );
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';
    if (diff < 7) return '$diff hari lalu';
    return Formatters.formatDate('${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}');
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.isIos});

  final bool isIos;

  @override
  Widget build(BuildContext context) {
    const body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.history_rounded, size: 56, color: AppColors.textMuted),
        SizedBox(height: 12),
        Text(
          'Belum ada riwayat',
          style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
        ),
        SizedBox(height: 4),
        Text(
          'Film yang kamu putar akan muncul di sini.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      ],
    );
    return Center(
      child: isIos
          ? const GlassContainer(
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              child: body,
            )
          : body,
    );
  }
}
