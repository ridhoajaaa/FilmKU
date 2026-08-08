import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Result of a playlist rewrite: the rewritten text plus a validity flag
/// (a playlist is invalid when it contains no media URI to rewrite — e.g.
/// the CDN returned an error page).
class _Rewritten {
  _Rewritten(this.playlist, this.isValid);
  final String playlist;
  final bool isValid;
}

/// ---------------------------------------------------------------------------
/// Local HLS relay for native playback of "video-in-image" streams.
///
/// The 2vcdn player serves its HLS segments as FAKE PNG files (a 70-byte PNG
/// header — IHDR/IDAT/IEND — prepended to raw MPEG-TS). Browsers tolerate
/// this, but libmpv / ExoPlayer / AVPlayer reject it (ffmpeg sees `png`
/// codec + "Invalid data"). Verified on-device 2026-08: stripping the 70-byte
/// header makes the exact same bytes play in mpv (h264 1728x720 + AAC).
///
/// [HlsRelay] runs a tiny HTTP server on loopback that:
///   1. Serves the 2vcdn master/variant playlists REWRITTEN so every segment
///      URI points back at this relay.
///   2. Fetches each original segment, strips the PNG wrapper, and serves the
///      clean MPEG-TS to the player.
///
/// The player (mpv/media_kit) therefore only ever talks to 127.0.0.1 — a
/// native-friendly, ad-free HLS stream with zero WebView involvement.
/// ---------------------------------------------------------------------------
class HlsRelay {
  HlsRelay._();

  /// Singleton — the relay must stay alive for the whole playback session
  /// (the player streams segments lazily long after `serve()` returns).
  static final HlsRelay instance = HlsRelay._();

  /// First 8 bytes of a PNG (`\x89PNG\r\n\x1a\n`) — every wrapped segment
  /// starts with this. Verified constant 70-byte wrapper on 2vcdn segments
  /// (2026-08): signature + IHDR(13) + IDAT(13) + IEND(0) = 8+25+25+12 = 70.
  static const List<int> _pngSignature = [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A
  ];

  HttpServer? _server;

  /// Single-flight guard for the bind: two concurrent [serve] calls (e.g.
  /// auto-capture + visible flow racing) must never both pass `_server ==
  /// null` and leak the first bound server (reviewer finding 2026-08).
  Future<void>? _bindFuture;
  final _dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 '
            'Mobile Safari/537.36',
        'Accept': '*/*',
      },
      responseType: ResponseType.bytes,
      followRedirects: true,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  bool get isRunning => _server != null;

  /// Current loopback port of the bound relay server, or null when not
  /// running. [PlayerScreen.reviveRelaySources] compares a cached relay URL's
  /// port against this to tell a LIVE relay URL (same session, keep as-is)
  /// from a stale one (disposed relay or another session's port → re-serve).
  int? get port => _server?.port;

  /// One-shot external-subtitle slots served on demand (`/filmku-sub.srt`).
  ///
  /// 2026-08 on-device root cause: the ONLY subtitle-attach form that works
  /// with the Android media-kit mpv build is an HTTP URL — `sub-add` rejects
  /// `file://` URIs AND plain filesystem paths with "Can not open external
  /// file" (three consecutive Android logcats: fetched OK, attach failed
  /// every time). HTTP URLs load fine (media-kit issue #394 + this relay
  /// already streams the video over HTTP to the same mpv instance), so the
  /// player serves the fetched SRT from this in-memory slot instead of a
  /// file.
  final Map<int, String> _subtitleSlots = {};

  /// Binds the loopback server if needed and returns the port — lets the
  /// player serve external subtitles over HTTP even for streams that do NOT
  /// need the PNG-stripping relay (direct m3u8 etc.). Idempotent.
  Future<int?> ensureRunning() async {
    await _ensureBound();
    return _server?.port;
  }

  /// Registers [content] (raw SRT/WebVTT text) under [tmdbId] so that
  /// `GET /filmku-sub.srt?tmdbId={tmdbId}` and the injected HLS subtitle
  /// track's `.vtt` segment serve it to the player.
  void serveSubtitle(int tmdbId, String content) {
    _subtitleSlots[tmdbId] = content;
  }

  void clearSubtitle(int tmdbId) {
    _subtitleSlots.remove(tmdbId);
  }

  /// Starts the relay (idempotent) and returns the rewritten master-playlist
  /// URL for [masterUrl], or null if the master cannot be fetched.
  Future<String?> serve(String masterUrl) async {
    try {
      // Bind FIRST: rewriting playlists builds the relay URIs from the
      // loopback port, so the server must exist before `_rewritePlaylist`
      // runs. The earlier bind-after-validate order dereferenced a NULL
      // `_server` inside `_relayUri` (Null check operator used on a null
      // value) which the swallow-all catch turned into a silent null — the
      // on-device `relay=failed` root cause (2026-08 syslog: the direct m3u8
      // extracted fine, `twoVcdnDirect=...` set, but `relay=failed`). The
      // bind is single-flight via [_ensureBound], and an invalid master
      // disposes the server again, so no bound-but-unused server leaks.
      await _ensureBound();
      final body = await _fetch(masterUrl);
      final rewritten = _rewritePlaylist(body, masterUrl);
      if (!rewritten.isValid) {
        await dispose();
        return null;
      }
      return 'http://127.0.0.1:${_server!.port}/master.m3u8'
          '?src=${Uri.encodeComponent(masterUrl)}';
    } catch (_) {
      return null;
    }
  }

  /// Binds the loopback server exactly once, sharing the in-flight bind
  /// across concurrent [serve] calls.
  Future<void> _ensureBound() {
    if (_server != null) return Future.value();
    return _bindFuture ??= _doBind();
  }

  Future<void> _doBind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _bindFuture = null;
    _listen();
  }

  /// Stops the server. Called when the player screen is disposed.
  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _bindFuture = null;
  }

  // -------------------------------------------------------------------------
  // Request handling
  // -------------------------------------------------------------------------

  void _listen() {
    _server!.listen((request) async {
      try {
        if (request.uri.path == '/filmku-sub.srt') {
          await _serveSubtitle(request);
          return;
        }
        if (request.uri.path == '/filmku-sub.m3u8') {
          await _serveSubtitlePlaylist(request);
          return;
        }
        if (request.uri.path == '/filmku-sub.vtt') {
          await _serveSubtitleVtt(request);
          return;
        }
        final src = request.uri.queryParameters['src'];
        if (src == null || src.isEmpty) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }
        if (request.uri.path.endsWith('.m3u8')) {
          await _servePlaylist(request, src);
        } else {
          await _serveSegment(request, src);
        }
      } catch (_) {
        try {
          request.response.statusCode = HttpStatus.badGateway;
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  /// Serves a registered external subtitle (`/filmku-sub.srt?tmdbId={id}`)
  /// as plain text. The `.srt` extension in the URL is the strong format
  /// hint mpv's demuxer needs when loading a remote subtitle.
  Future<void> _serveSubtitle(HttpRequest request) async {
    final id = int.tryParse(request.uri.queryParameters['tmdbId'] ?? '');
    final content = id != null ? _subtitleSlots[id] : null;
    if (content == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response.headers.contentType =
        ContentType('text', 'plain', charset: 'utf-8');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.add(utf8.encode(content));
    await request.response.close();
  }

  Future<void> _servePlaylist(HttpRequest request, String src) async {
    final body = await _fetch(src);
    final rewritten = _rewritePlaylist(body, src);
    if (!rewritten.isValid) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }
    var text = rewritten.playlist;
    // MASTER playlists (they carry #EXT-X-STREAM-INF) get an injected HLS
    // SUBTITLES track: mpv Android's reduced libmpv rejects sub-add for EVERY
    // external form (file, path, file://, http:// — "Can not open external
    // file", 2026-08 logcats) yet parses HLS EXT-X-MEDIA tracks natively.
    // The player appends tmdbId to the master URL so the track is present
    // from the FIRST fetch; the player selects it once the SRT is registered
    // (~2s in) — mpv fetches the injected PLAYLIST, then the WebVTT segment
    // (libass=true renders it).
    //
    // v1.3.45 lesson: the EXT-X-MEDIA URI MUST point at a PLAYLIST (.m3u8),
    // never at the .vtt segment directly — ffmpeg's hls demuxer tries to
    // parse the URI's content AS a playlist, so a bare WebVTT file yields
    // `parse_playlist error Invalid argument` and the demuxer REJECTS the
    // whole master (video never started: durationKnownMs=0, STARTUP_TIMEOUT;
    // verified with ffmpeg on the laptop). The playlist route returns a valid
    // HLS subtitle playlist whose segment is the .vtt route.
    // Injection is opt-in via the player-appended tmdbId query param ONLY
    // (no fallback to a stored field — a stale tmdbId from a previous movie
    // must never inject a dead track into the NEXT movie's playlist).
    final tmdbId = int.tryParse(request.uri.queryParameters['tmdbId'] ?? '');
    if (tmdbId != null && body.contains('#EXT-X-STREAM-INF')) {
      text = _injectSubtitleTrack(text, tmdbId);
    }
    request.response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.add(utf8.encode(text));
    await request.response.close();
  }

  /// Injects an `#EXT-X-MEDIA:TYPE=SUBTITLES` track into a rewritten MASTER
  /// playlist and links its group from every variant stream. The track is
  /// DEFAULT=NO/AUTOSELECT=NO so mpv lists it WITHOUT selecting it at open
  /// (the subtitle is registered ~2s later — an early select would fetch an
  /// empty WebVTT and cache it). The player selects it explicitly once the
  /// SRT is registered.
  ///
  /// HLS spec: `#EXTM3U` MUST stay the FIRST line (a tag before it makes
  /// ffmpeg's hls demuxer reject the whole playlist, killing the video too),
  /// and the EXT-X-MEDIA URI MUST point at a subtitle PLAYLIST — the .m3u8
  /// route, NOT the .vtt segment (see the v1.3.45 regression note above).
  String _injectSubtitleTrack(String playlist, int tmdbId) {
    final port = _server!.port;
    const name = 'FilmKU Indonesia';
    final media = '#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="filmku",'
        'NAME="$name",DEFAULT=NO,AUTOSELECT=NO,FORCED=NO,LANGUAGE="id",'
        'URI="http://127.0.0.1:$port/filmku-sub.m3u8?tmdbId=$tmdbId"';
    // Link the subtitle group from every variant stream line.
    final linked = playlist.replaceAllMapped(
      RegExp(r'(#EXT-X-STREAM-INF:[^\n]*)'),
      (m) => '${m.group(1)},SUBTITLES="filmku"',
    );
    return linked.startsWith('#EXTM3U\n')
        ? linked.replaceFirst('#EXTM3U\n', '#EXTM3U\n$media\n')
        : '$media\n$linked';
  }

  /// Serves the HLS subtitle PLAYLIST for a registered external subtitle
  /// (`/filmku-sub.m3u8?tmdbId={id}`). The playlist is ALWAYS valid HLS (mpv
  /// fetches it when the injected track is selected); its single segment is
  /// the /filmku-sub.vtt route which serves the WebVTT content (empty VTT
  /// until the slot is registered — a safety net, since the player only
  /// selects the track after registration).
  Future<void> _serveSubtitlePlaylist(HttpRequest request) async {
    final id = int.tryParse(request.uri.queryParameters['tmdbId'] ?? '');
    // The segment URI is RELATIVE to the playlist URL (same host/port), so
    // mpv resolves it against the relay without needing an absolute URL.
    final playlist = '#EXTM3U\n'
        '#EXT-X-TARGETDURATION:10\n'
        '#EXT-X-VERSION:3\n'
        '#EXTINF:10.0,\n'
        'filmku-sub.vtt?tmdbId=$id\n'
        '#EXT-X-ENDLIST\n';
    request.response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.add(utf8.encode(playlist));
    await request.response.close();
  }

  /// Serves a registered external subtitle (`/filmku-sub.vtt?tmdbId={id}`)
  /// as WebVTT — the HLS-track form the Android libmpv build actually loads.
  /// Returns a valid empty VTT when the slot is not yet registered (mpv only
  /// requests this URL AFTER the track is selected, which the player does
  /// only once the content exists, so this is just a safety net).
  Future<void> _serveSubtitleVtt(HttpRequest request) async {
    final id = int.tryParse(request.uri.queryParameters['tmdbId'] ?? '');
    final content = id != null ? _subtitleSlots[id] : null;
    final vtt = content == null ? 'WEBVTT\n\n' : HlsRelay.srtToVtt(content);
    request.response.headers.contentType =
        ContentType('text', 'vtt', charset: 'utf-8');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.add(utf8.encode(vtt));
    await request.response.close();
  }

  /// Converts SRT text to WebVTT (the HLS subtitle format). Handles BOM,
  /// CRLF, and SRT's comma timestamps (`00:00:01,000`) → WebVTT dots
  /// (`00:00:01.000`). SRT numeric index lines become valid cue identifiers.
  static String srtToVtt(String srt) {
    var s = srt.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (s.startsWith('\uFEFF')) s = s.substring(1);
    s = s.replaceAllMapped(
      RegExp(r'(\d{2}:\d{2}:\d{2}),(\d{3})'),
      (m) => '${m.group(1)}.${m.group(2)}',
    );
    return 'WEBVTT\n\n$s\n';
  }

  Future<void> _serveSegment(HttpRequest request, String src) async {
    final bytes = await _fetchBytes(src);
    final stripped = stripPngWrapper(bytes);
    // Content type by SOURCE extension (not the relay route): WebVTT
    // subtitle chunks must be served as text/vtt or the player's demuxer may
    // reject them (2026-08: external subtitle tracks through the relay).
    final srcPath = (Uri.tryParse(src)?.path ?? '').toLowerCase();
    final contentType = srcPath.endsWith('.vtt')
        ? ContentType('text', 'vtt')
        : ContentType('video', 'mp2t');
    request.response.headers.contentType = contentType;
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.add(stripped);
    await request.response.close();
  }

  // -------------------------------------------------------------------------
  // Playlist rewriting
  // -------------------------------------------------------------------------

  _Rewritten _rewritePlaylist(String body, String baseUrl) {
    final base = Uri.tryParse(baseUrl);
    final out = <String>[];
    var mediaLines = 0;
    final uriAttr = RegExp('URI="([^"]*)"');

    for (final rawLine in body.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        out.add(rawLine);
        continue;
      }
      if (line.startsWith('#')) {
        // #EXT-X-KEY / #EXT-X-MEDIA / #EXT-X-MAP carry URI="..." attributes.
        final rewritten = line.replaceAllMapped(uriAttr, (m) {
          final resolved = _resolve(base, m.group(1) ?? '');
          if (resolved == null) return m.group(0)!;
          mediaLines++;
          return 'URI="${_relayUri(resolved)}"';
        });
        out.add(rewritten);
        continue;
      }
      // A bare URI line: variant playlist (.m3u8) or segment.
      final resolved = _resolve(base, line);
      if (resolved == null) {
        out.add(rawLine);
        continue;
      }
      mediaLines++;
      out.add(_relayUri(resolved));
    }
    return _Rewritten(out.join('\n'), mediaLines > 0);
  }

  /// Resolves [ref] against [base], keeping the original query string when
  /// the URI already carries one. Returns null when unresolvable.
  String? _resolve(Uri? base, String ref) {
    if (base == null) return null;
    try {
      if (ref.startsWith('http://') || ref.startsWith('https://')) return ref;
      return base.resolve(ref).toString();
    } catch (_) {
      return null;
    }
  }

  /// Maps an absolute original URL to this relay: playlists go through
  /// `/…m3u8`, everything else through `/…ts`.
  ///
  /// The classification checks the URL **path** (before any query), so a
  /// variant URI carrying a query string (`index.m3u8?token=x`) is still
  /// routed as a playlist (reviewer finding 2026-08).
  String _relayUri(String absoluteUrl) {
    final port = _server!.port;
    final path = (Uri.tryParse(absoluteUrl)?.path ?? '').toLowerCase();
    // Route by source extension so the served content type matches (m3u8 →
    // playlist, vtt → subtitle text, everything else → MPEG-TS segment).
    final route = path.endsWith('.m3u8')
        ? 'media.m3u8'
        : (path.endsWith('.vtt') ? 'media.vtt' : 'segment.ts');
    return 'http://127.0.0.1:$port/$route?src=${Uri.encodeComponent(absoluteUrl)}';
  }

  // -------------------------------------------------------------------------
  // Fetching + PNG strip
  // -------------------------------------------------------------------------

  Future<String> _fetch(String url) async {
    final resp = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return utf8.decode(resp.data ?? const [], allowMalformed: true);
  }

  Future<Uint8List> _fetchBytes(String url) async {
    final resp = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(resp.data ?? const []);
  }

  /// Removes the leading fake-PNG wrapper from a 2vcdn segment.
  ///
  /// Robust strategy: scan for the first MPEG-TS sync byte (0x47) that is
  /// followed by another 0x47 exactly 188 bytes later (TS packet size), and
  /// serve from there. This handles the observed constant 70-byte wrapper AND
  /// any wrapper-size drift by the CDN. Non-wrapped data (already-TS, or an
  /// error page) is passed through untouched.
  static Uint8List stripPngWrapper(Uint8List bytes) {
    if (bytes.length < 188) return bytes;
    // Fast path: exact PNG signature → find the TS sync inside.
    if (bytes.length >= 8) {
      var isPng = true;
      for (var i = 0; i < 8; i++) {
        if (bytes[i] != _pngSignature[i]) {
          isPng = false;
          break;
        }
      }
      if (isPng) {
        for (var i = 0; i < bytes.length - 188; i++) {
          if (bytes[i] == 0x47 && bytes[i + 188] == 0x47) {
            return Uint8List.sublistView(bytes, i);
          }
        }
        // PNG header but no 188-stride sync found — pass through unchanged.
        return bytes;
      }
    }
    return bytes;
  }
}
