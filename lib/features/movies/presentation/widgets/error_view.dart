import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.secondaryLabel,
    this.onSecondary,
    this.secondaryHint,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;

  /// Optional secondary action (e.g. "Play in WebView" fallback).
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Optional small hint shown under the secondary action (e.g. "May show
  /// source ads"). Null renders no hint.
  final String? secondaryHint;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.cloud_off, color: AppColors.textMuted, size: 34),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
            ),
          ),
        ],
        if (secondaryLabel != null && onSecondary != null) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onSecondary,
            icon: const Icon(Icons.language, size: 18),
            label: Text(secondaryLabel!),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
          ),
          if (secondaryHint != null) ...[
            const SizedBox(height: 6),
            Text(
              secondaryHint!,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ],
    );
    return compact ? content : Center(child: content);
  }
}
