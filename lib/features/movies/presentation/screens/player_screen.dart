import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/movie_details.dart';
import '../../domain/entities/video_source.dart';
import '../providers/movie_providers.dart';
import '../widgets/error_view.dart';
import '../widgets/video_player_controls.dart';

/// Native, ad-free video player. Extracts direct stream links via the
/// SourceAggregator and plays them with `video_player` — no ads render.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.movieId});

  final int movieId;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  VideoPlayerController? _controller;
  VideoSource? _selected;
  List<VideoSource> _sources = const <VideoSource>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enterLandscape();
      _loadSources();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _restorePortrait();
    super.dispose();
  }

  Future<void> _enterLandscape() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _restorePortrait() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _loadSources() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sources =
          await ref.read(videoSourcesProvider(widget.movieId).future);
      if (!mounted) return;
      setState(() => _sources = sources);

      final playable = sources.where((s) => s.isPlayable).toList();
      if (playable.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No playable stream found for this movie.\n'
              'Try again or enable more sources in Settings.';
        });
        return;
      }
      await _initPlayer(playable.first);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _initPlayer(VideoSource source) async {
    final old = _controller;
    _controller = null;
    await old?.dispose();

    final url = source.videoUrl;
    if (url == null) {
      setState(() {
        _selected = source;
        _loading = false;
        _error = '${source.label} has no direct stream.';
      });
      return;
    }

    setState(() {
      _selected = source;
      _loading = true;
      _error = null;
    });

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load the stream from ${source.label}. '
              'Try another source.';
        });
      }
    }
  }

  void _pickSource() async {
    final picked = await showModalBottomSheet<VideoSource>(
      context: context,
      backgroundColor: AppColors.charcoal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Source',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final source in _sources)
                    ListTile(
                      leading: Icon(
                        source.isPlayable
                            ? Icons.play_circle_fill
                            : Icons.error_outline,
                        color: source.isPlayable
                            ? AppColors.accent
                            : AppColors.textMuted,
                      ),
                      title: Text(
                        source.label,
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                      subtitle: Text(
                        '${source.quality} • ${source.sourceId}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      trailing: source.sourceId == _selected?.sourceId
                          ? const Icon(Icons.check_circle,
                              color: AppColors.accent)
                          : null,
                      onTap: source.isPlayable
                          ? () => Navigator.pop(context, source)
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      await _initPlayer(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched unconditionally at the top of build — Riverpod requires the
    // set of watched providers to stay stable across rebuilds.
    final details = ref.watch(movieDetailsProvider(widget.movieId));
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _buildBody(title: _movieTitleFrom(details)),
      ),
    );
  }

  Widget _buildBody({required String title}) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Finding stream sources…',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return ErrorView(
        message: _error!,
        onRetry: _loadSources,
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const Center(
        child: Text(
          'Player not initialized',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        if (controller.value.isInitialized)
          CustomVideoControls(
            controller: controller,
            title: title,
            sourceLabel: _selected?.label,
            onClose: () => context.pop(),
            onSelectSource: _sources.length > 1 ? _pickSource : null,
          ),
      ],
    );
  }

  static String _movieTitleFrom(AsyncValue<MovieDetails> details) {
    if (details is AsyncData) {
      final title = details.value?.movie.title;
      if (title != null && title.isNotEmpty) return title;
    }
    return 'Now Playing';
  }
}
