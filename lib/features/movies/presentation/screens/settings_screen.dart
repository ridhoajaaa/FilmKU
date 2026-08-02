import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/local/settings_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/datasources/stream_source_datasource.dart';
import '../providers/settings_provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final apiKey =
        settings.apiKey.isNotEmpty ? settings.apiKey : AppConstants.tmdbApiKey;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        // iOS: clear the floating glass capsule so the last tile is never
        // hidden behind it (extendBody content scrolls under the bar).
        padding: EdgeInsets.only(
          bottom: Theme.of(context).platform == TargetPlatform.iOS ? 110 : 0,
        ),
        children: [
          const _SectionTitle('TMDB API'),
          ListTile(
            leading: const Icon(Icons.key, color: AppColors.accent),
            title: const Text('API Key'),
            subtitle: Text(
              apiKey.isEmpty
                  ? 'Not set — movies will not load'
                  : '•••••••••••• (tap to edit)',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            trailing: const Icon(Icons.edit, size: 20),
            onTap: () => _editApiKey(settings.apiKey),
          ),
          const Divider(height: 24),
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
            secondary:
                const Icon(Icons.play_circle_outline, color: AppColors.accent),
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
          SwitchListTile(
            secondary: const Icon(Icons.http, color: AppColors.accent),
            title: const Text('Browser headers (experimental)'),
            subtitle: const Text(
              'Send Referer/Origin/User-Agent on native media requests. '
              'Some CDNs (e.g. VidLink) reject bare ExoPlayer fetches — '
              'try this if a source fails to play natively.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            value: settings.browserHeaders,
            onChanged: (value) =>
                ref.read(settingsProvider.notifier).setBrowserHeaders(value),
          ),
          const Divider(height: 24),
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
          const Divider(height: 24),
          const _SectionTitle('About'),
          const ListTile(
            leading: Icon(Icons.movie_filter, color: AppColors.accent),
            title: Text('FilmKU'),
            subtitle: Text(
              'Version 1.0.0\nStream movies. Zero ads.\n'
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.accent,
        ),
      ),
    );
  }
}
