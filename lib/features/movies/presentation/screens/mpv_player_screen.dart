import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../widgets/error_view.dart';
import '../widgets/player_swipe_dismiss.dart';

/// Arguments for the mpv native player route (WebView handoff streams).
class MpvPlayerArgs {
  const MpvPlayerArgs({
    required this.url,
    required this.title,
    required this.sourceLabel,
    this.startAt = Duration.zero,
  });

  /// Direct `.m3u8`/`.mp4` URL captured from inside the WebView fallback.
  final String url;

  /// Movie title shown in the top bar.
  final String title;

  /// Human-readable provider name.
  final String sourceLabel;

  /// Where the WebView playback was, to resume from.
  final Duration startAt;
}

/// Native player backed by libmpv (`media_kit`).
///
/// ExoPlayer's MediaCodec renderer crashes on some HLS MPEG-TS streams on
/// certain devices (observed on-device: `MediaCodecVideoRenderer error ...`
/// on a Xiaomi while the same stream plays fine in a WebView). libmpv
/// transparently falls back to software decoding, so this screen is the
/// native destination for streams handed off from the WebView fallback.
///
/// Pops with `true` when playback failed (the caller should return to the
/// WebView fallback), `false`/null on a normal close.
class MpvPlayerScreen extends StatefulWidget {
  const MpvPlayerScreen({super.key, required this.args});

  final MpvPlayerArgs args;

  @override
  State<MpvPlayerScreen> createState() => _MpvPlayerScreenState();
}

class _MpvPlayerScreenState extends State<MpvPlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  bool _failed = false;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enterLandscape();
    });
    _listenForErrors();
    _open();
  }

  Future<void> _open() async {
    debugPrint(
      'FILMKU_MPV_OPEN url=${widget.args.url} '
      'startAt=${widget.args.startAt.inMilliseconds}',
    );
    try {
      await _player.open(Media(widget.args.url), play: true);
      if (widget.args.startAt > Duration.zero) {
        await _player.seek(widget.args.startAt);
      }
      debugPrint('FILMKU_MPV_OPENED');
    } catch (e) {
      debugPrint('FILMKU_MPV_OPEN_ERROR $e');
      _markFailed('Failed to open stream.');
    }
  }

  void _listenForErrors() {
    _errorSub = _player.stream.error.listen((error) {
      debugPrint('FILMKU_MPV_ERROR $error');
      _markFailed('Playback error: $error');
    });
  }

  void _markFailed(String detail) {
    if (!mounted || _failed) return;
    setState(() {
      _failed = true;
    });
    debugPrint('FILMKU_MPV_FAILED $detail');
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _restorePortrait();
    _player.dispose();
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

  void _close({bool failed = false}) => context.pop<bool>(failed);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        // iOS: swipe down anywhere to leave fullscreen (no need to kill the
        // app from the background). Non-iOS platforms are a pass-through.
        child: PlayerSwipeDismiss(
          onDismiss: () => _close(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // libmpv renders + letterboxes; the built-in adaptive controls
              // provide play/pause, seek bar and volume.
              Video(controller: _videoController),
              // Title + source chip + close — always accessible (immersive
              // mode hides the system affordances).
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(
                  children: [
                    _RoundIconButton(
                      icon: Icons.close,
                      tooltip: 'Close player',
                      onPressed: () => _close(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.args.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        widget.args.sourceLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_failed)
                Center(
                  child: ErrorView(
                    message:
                        'Native playback failed for ${widget.args.sourceLabel}.',
                    onRetry: () {
                      setState(() => _failed = false);
                      _open();
                    },
                    secondaryLabel: 'Back to WebView',
                    onSecondary: () => _close(failed: true),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 22),
        tooltip: tooltip,
      ),
    );
  }
}
