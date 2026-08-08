import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/local/settings_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/datasources/stream_source_datasource.dart';
import '../providers/settings_provider.dart';
import '../providers/watch_history_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late Set<String> _disabledSources;

  @override
  void initState() {
    super.initState();
    _disabledSources = {
      for (final e in SourceAggregator.extractors)
        if (!SettingsService.instance.isSourceEnabled(e.sourceId)) e.sourceId,
    };
  }

  Future<void> _editApiKey(String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('TMDB API Key'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Enter your API key (v3 auth)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      ref.read(settingsProvider.notifier).setApiKey(result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key saved.')),
      );
    }
  }

  /// Optional subdl.com subtitle API key (free from subdl.com → account →
  /// API). When set, subdl becomes a THIRD external subtitle source (after
  /// YIFY + SubtitleCat) — useful for movies neither keyless source covers.
  Future<void> _editSubdlKey(String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Subdl API Key'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Free key: subdl.com → account → API',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      ref.read(settingsProvider.notifier).setSubdlApiKey(result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subdl key saved.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final apiKey =
        settings.apiKey.isNotEmpty ? settings.apiKey : AppConstants.tmdbApiKey;

    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        // iOS: clear the floating glass capsule so the last tile is never
        // hidden behind it (extendBody content scrolls under the bar).
        padding: EdgeInsets.only(
          bottom: isIos ? 110 : 0,
        ),
        children: [
          const _SectionTitle('TMDB API'),
          // iOS: REAL liquid-glass row (shader-based GlassListTile).
          // Android: classic Material ListTile.
          if (isIos)
            GlassListTile(
              leading: const Icon(Icons.key, color: Colors.white70),
              title: const Text('API Key'),
              subtitle: Text(
                apiKey.isEmpty
                    ? 'Not set — movies will not load'
                    : '•••••••••••• (tap to edit)',
              ),
              trailing: const Icon(Icons.edit, size: 20),
              onTap: () => _editApiKey(settings.apiKey),
            )
          else
            ListTile(
              leading: const Icon(Icons.key, color: AppColors.accent),
              title: const Text('API Key'),
              subtitle: Text(
                apiKey.isEmpty
                    ? 'Not set — movies will not load'
                    : '•••••••••••• (tap to edit)',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              trailing: const Icon(Icons.edit, size: 20),
              onTap: () => _editApiKey(settings.apiKey),
            ),
          const Divider(height: 24),
          // Optional subdl.com subtitle API key (third subtitle source).
          if (isIos)
            GlassGroupedSection(
              header: const _GlassSectionHeader('Subtitles'),
              children: [
                GlassListTile(
                  leading:
                      const Icon(Icons.closed_caption, color: Colors.white70),
                  title: const Text('Subdl API Key (opsional)'),
                  subtitle: Text(
                    settings.subdlApiKey.isEmpty
                        ? 'Tidak diatur — subtitle eksternal dari YIFY + '
                            'SubtitleCat saja. Gratis: subdl.com → daftar → API'
                        : '•••••••••••• (tap to edit)',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  trailing: const Icon(Icons.edit, size: 20),
                  onTap: () => _editSubdlKey(settings.subdlApiKey),
                ),
              ],
            )
          else ...[
            const _SectionTitle('Subtitles'),
            ListTile(
              leading:
                  const Icon(Icons.closed_caption, color: AppColors.accent),
              title: const Text('Subdl API Key (opsional)'),
              subtitle: Text(
                settings.subdlApiKey.isEmpty
                    ? 'Tidak diatur — subtitle eksternal dari YIFY + '
                        'SubtitleCat saja. Gratis: subdl.com → daftar → API'
                    : '•••••••••••• (tap to edit)',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              trailing: const Icon(Icons.edit, size: 20),
              onTap: () => _editSubdlKey(settings.subdlApiKey),
            ),
          ],
          const Divider(height: 24),
          // iOS: REAL liquid-glass grouped section (shader-based
          // GlassGroupedSection + GlassListTile with a trailing Switch) — the
          // extraction toggles read as an iOS-26 grouped table. Android keeps
          // the classic Material SwitchListTiles.
          if (isIos)
            GlassGroupedSection(
              header: const _GlassSectionHeader('Stream Extraction'),
              children: [
                _glassSwitchTile(
                  leading: const Icon(Icons.dns, color: Colors.white70),
                  title: 'Headless extraction',
                  subtitle: 'Use an invisible WebView to find direct stream '
                      'links when the quick scan fails.',
                  value: settings.headlessExtraction,
                  onChanged: (value) => ref
                      .read(settingsProvider.notifier)
                      .setHeadlessExtraction(value),
                ),
                _glassSwitchTile(
                  leading: const Icon(
                    Icons.play_circle_outline,
                    color: Colors.white70,
                  ),
                  title: 'WebView fallback',
                  subtitle: 'If no direct stream is found, open the source '
                      'page in a visible WebView (may show ads).',
                  value: settings.fallbackWebview,
                  onChanged: (value) => ref
                      .read(settingsProvider.notifier)
                      .setFallbackWebview(value),
                ),
              ],
            )
          else ...[
            const _SectionTitle('Stream Extraction'),
            SwitchListTile(
              secondary: const Icon(Icons.dns, color: AppColors.accent),
              title: const Text('Headless extraction'),
              subtitle: const Text(
                'Use an invisible WebView to find direct stream links when '
                'the quick scan fails.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              value: settings.headlessExtraction,
              onChanged: (value) => ref
                  .read(settingsProvider.notifier)
                  .setHeadlessExtraction(value),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.play_circle_outline,
                  color: AppColors.accent),
              title: const Text('WebView fallback'),
              subtitle: const Text(
                'If no direct stream is found, open the source page in a '
                'visible WebView (may show ads).',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              value: settings.fallbackWebview,
              onChanged: (value) =>
                  ref.read(settingsProvider.notifier).setFallbackWebview(value),
            ),
          ],
          const Divider(height: 24),
          if (isIos)
            GlassGroupedSection(
              header: const _GlassSectionHeader('Video Sources'),
              children: [
                for (final extractor in SourceAggregator.extractors)
                  _glassSwitchTile(
                    leading: const Icon(Icons.link, color: Colors.white70),
                    title: extractor.label,
                    subtitle: extractor.sourceId,
                    value: !_disabledSources.contains(extractor.sourceId),
                    onChanged: (value) => setState(() {
                      final service = SettingsService.instance;
                      if (value) {
                        _disabledSources.remove(extractor.sourceId);
                      } else {
                        _disabledSources.add(extractor.sourceId);
                      }
                      service.setSourceEnabled(extractor.sourceId, value);
                    }),
                  ),
              ],
            )
          else ...[
            const _SectionTitle('Video Sources'),
            ...SourceAggregator.extractors.map(
              (extractor) => SwitchListTile(
                secondary: const Icon(Icons.link, color: AppColors.accent),
                title: Text(extractor.label),
                subtitle: Text(
                  extractor.sourceId,
                  style:
                      const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                value: !_disabledSources.contains(extractor.sourceId),
                onChanged: (value) => setState(() {
                  final service = SettingsService.instance;
                  if (value) {
                    _disabledSources.remove(extractor.sourceId);
                  } else {
                    _disabledSources.add(extractor.sourceId);
                  }
                  service.setSourceEnabled(extractor.sourceId, value);
                }),
              ),
            ),
          ],
          const Divider(height: 24),
          // Full watch history (all plays, including finished ones) — moved
          // here from Home (2026-08 user report: the Home link looked bad).
          // Shown only when there is something to show.
          if (isIos)
            GlassGroupedSection(
              header: const _GlassSectionHeader('Activity'),
              children: [
                _GlassHistoryTile(
                  onTap: () => context.push('/history'),
                ),
              ],
            )
          else ...[
            const _SectionTitle('Activity'),
            const _AndroidHistoryTile(),
          ],
          const Divider(height: 24),
          const _SectionTitle('About'),
          // iOS: REAL liquid-glass row (shader-based GlassListTile).
          // Android: classic Material ListTile.
          //
          // `AppConstants.appVersion` is a const, so the interpolated string
          // is const-foldable — the whole tile stays const (analyzer keeps
          // prefer_const_constructors happy).
          if (isIos)
            const GlassListTile(
              leading: Icon(Icons.movie_filter, color: Colors.white70),
              title: Text('FilmKU'),
              subtitle: Text(
                'Version ${AppConstants.appVersion}\nStream movies. Zero ads.\n'
                'Only stream content you are legally entitled to.',
              ),
            )
          else
            const ListTile(
              leading: Icon(Icons.movie_filter, color: AppColors.accent),
              title: Text('FilmKU'),
              subtitle: Text(
                'Version ${AppConstants.appVersion}\nStream movies. Zero ads.\n'
                'Only stream content you are legally entitled to.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    // NOTE: not const — the color depends on the runtime platform (iOS gets
    // the neutral light-gray accent, Android keeps the brand red).
    final color = Theme.of(context).platform == TargetPlatform.iOS
        ? const Color(0xFF9E9EA8)
        : AppColors.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: color,
        ),
      ),
    );
  }
}

/// iOS-only header for [GlassGroupedSection] — same uppercase caption look as
/// [_SectionTitle] but styled for the glass grouped table (iOS 26 settings).
class _GlassSectionHeader extends StatelessWidget {
  const _GlassSectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: Color(0xFF9E9EA8),
        ),
      ),
    );
  }
}

/// iOS glass row that opens the full watch history screen — lives in Settings
/// (moved from Home, 2026-08: the Home link looked bad). Shows the entry count
/// when there is history, a hint otherwise.
class _GlassHistoryTile extends ConsumerWidget {
  const _GlassHistoryTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(watchHistoryProvider).length;
    return GlassListTile(
      leading: const Icon(Icons.history_rounded, color: Colors.white70),
      title: const Text('Riwayat tontonan'),
      subtitle: Text(
        count == 0
            ? 'Belum ada film yang diputar'
            : '$count film pernah diputar',
        style: const TextStyle(fontSize: 12, color: Colors.white54),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
  }
}

/// Android ListTile that opens the full watch history screen (same move as
/// [_GlassHistoryTile]: history lives in Settings, not Home).
class _AndroidHistoryTile extends ConsumerWidget {
  const _AndroidHistoryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(watchHistoryProvider).length;
    return ListTile(
      leading: const Icon(Icons.history_rounded, color: AppColors.accent),
      title: const Text('Riwayat tontonan'),
      subtitle: Text(
        count == 0
            ? 'Belum ada film yang diputar'
            : '$count film pernah diputar',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      ),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: () => context.push('/history'),
    );
  }
}

/// Builds an iOS glass row with a trailing [Switch] (the GlassGroupedSection
/// equivalent of a Material [SwitchListTile]).
Widget _glassSwitchTile({
  required Widget leading,
  required String title,
  required String subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return GlassListTile(
    leading: leading,
    title: Text(title),
    subtitle: Text(
      subtitle,
      style: const TextStyle(fontSize: 12, color: Colors.white54),
    ),
    trailing: Switch(
      value: value,
      onChanged: onChanged,
    ),
    onTap: () => onChanged(!value),
  );
}
