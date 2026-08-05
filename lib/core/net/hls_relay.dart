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

  Future<void> _servePlaylist(HttpRequest request, String src) async {
    final body = await _fetch(src);
    final rewritten = _rewritePlaylist(body, src);
    if (!rewritten.isValid) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }
    request.response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.add(utf8.encode(rewritten.playlist));
    await request.response.close();
  }

  Future<void> _serveSegment(HttpRequest request, String src) async {
    final bytes = await _fetchBytes(src);
    final stripped = stripPngWrapper(bytes);
    request.response.headers.contentType = ContentType('video', 'mp2t');
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
    final route = path.endsWith('.m3u8') ? 'media.m3u8' : 'segment.ts';
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
