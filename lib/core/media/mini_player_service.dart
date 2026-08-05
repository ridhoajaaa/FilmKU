import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../net/hls_relay.dart';

/// A live playback session owned by [MiniPlayerService].
///
/// The Player/VideoController live HERE, not in the fullscreen player screen,
/// so that "pop up film" (minimize to a floating mini player) can keep the
/// exact same playback running when the fullscreen route pops — no re-open,
/// no position loss, seamless video + audio continuity.
class MiniPlayerSession {
  MiniPlayerSession({
    required this.player,
    required this.videoController,
    required this.url,
    required this.title,
    required this.sourceLabel,
    required this.httpHeaders,
  });

  final Player player;
  final VideoController videoController;

  /// Stream URL this session is playing (identity used to reuse vs. restart).
  final String url;
  final String title;
  final String sourceLabel;
  final Map<String, String> httpHeaders;

  /// True when [acquire] created this session (the caller must open the
  /// media); false when it reused an existing one (playback already running).
  bool fresh = true;
}

/// Singleton owner of the native player lifecycle.
///
/// 2026-08: the fullscreen mpv screen used to own its own `Player`, so
/// leaving fullscreen always killed playback. With [MiniPlayerService] the
/// player survives the route pop: `minimize()` keeps it playing in the
/// floating [MiniPlayerOverlay], while an explicit close (`stop()`) or a pop
/// that was not a minimize disposes it.
class MiniPlayerService extends ChangeNotifier {
  MiniPlayerService._();

  static final MiniPlayerService instance = MiniPlayerService._();

  MiniPlayerSession? _session;
  bool _minimized = false;

  MiniPlayerSession? get session => _session;

  /// Whether the current session has been minimized to the floating mini
  /// player (route popped but playback intentionally continues).
  bool get isMinimized => _minimized;

  bool get isActive => _session != null;

  /// Returns a session for [url], reusing the existing one when it is the
  /// same stream (resume from mini player / re-entry) and creating a fresh
  /// Player otherwise (stopping whatever was playing before).
  Future<MiniPlayerSession> acquire({
    required String url,
    required String title,
    required String sourceLabel,
    Map<String, String> httpHeaders = const <String, String>{},
  }) async {
    final existing = _session;
    if (existing != null && existing.url == url) {
      existing.fresh = false;
      _minimized = false;
      notifyListeners();
      return existing;
    }
    if (existing != null) {
      await stop();
    }
    // Android performance (2026-08): the default demuxer cache is 32MB; a
    // larger cache smooths slow CDNs. Hardware acceleration stays on.
    // libass=true enables EMBEDDED subtitle rendering (mpv `sub-visibility`
    // is 'no' by default in media_kit — the 2026-08 "movies have no
    // subtitles anymore" regression). Android needs the bundled Roboto font
    // for libass; iOS renders via its own font stack.
    final player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024,
        libass: true,
        libassAndroidFont: 'assets/fonts/Roboto-Regular.ttf',
        libassAndroidFontName: 'Roboto',
      ),
    );
    final videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    _session = MiniPlayerSession(
      player: player,
      videoController: videoController,
      url: url,
      title: title,
      sourceLabel: sourceLabel,
      httpHeaders: httpHeaders,
    )..fresh = true;
    _minimized = false;
    notifyListeners();
    return _session!;
  }

  /// Keeps the current session playing while the fullscreen route pops so
  /// the floating mini player can take over (YouTube-style "pop up film").
  void minimize() {
    if (_session == null) return;
    _minimized = true;
    notifyListeners();
  }

  /// Brings the session back to fullscreen (tapped the mini player).
  void expand() {
    if (_session == null) return;
    _minimized = false;
    notifyListeners();
  }

  /// Fully stops playback and disposes the native player + local HLS relay.
  Future<void> stop() async {
    final session = _session;
    _session = null;
    _minimized = false;
    notifyListeners();
    if (session != null) {
      try {
        await session.player.dispose();
      } catch (_) {
        // Best-effort teardown — a dispose race must never crash the app.
      }
    }
    // The local HLS relay serves the session's stream (it strips the fake-PNG
    // wrapper from every segment for the WHOLE session). It must outlive the
    // fullscreen route (mini player keeps pulling segments) and die only when
    // the session itself ends — exactly here, at [stop].
    try {
      await HlsRelay.instance.dispose();
    } catch (_) {
      // Best-effort teardown.
    }
  }
}
