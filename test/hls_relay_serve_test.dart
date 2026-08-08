// HlsRelay.serve() end-to-end against a real loopback fake CDN.
//
// Deliberately uses ONLY plain `test()` (no testWidgets / no
// TestWidgetsFlutterBinding): that binding swaps HttpOverrides so every HTTP
// request answers 400, which would make serve()'s warm-up fetch fail. A
// binding-free file keeps real loopback HTTP working.
//
// The regression this guards: serve() used to REWRITE before BINDING, so
// `_relayUri` dereferenced a null `_server` (Null check operator on null)
// and the swallow-all catch returned a silent null — the on-device
// `relay=failed` root cause (2026-08 syslog: twoVcdnDirect extracted fine,
// relay=null). It also proves the full master→variant→segment rewrite + PNG
// strip works through the REAL HlsRelay instance.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/core/net/hls_relay.dart';

void main() {
  test('serve() returns a working relay URL (regression: null-server crash)',
      () async {
    // Fake CDN on loopback: master -> variant -> PNG-wrapped TS segment.
    final cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${cdn.port}';
    final ts = Uint8List.fromList(List<int>.generate(
        188 * 3, (i) => i == 0 || i == 188 || i == 376 ? 0x47 : (i % 251)));
    final wrapped = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      ...List<int>.filled(62, 0), // rest of the 70-byte wrapper
      ...ts,
    ]);
    cdn.listen((request) async {
      switch (request.uri.path) {
        case '/master.m3u8':
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          request.response.write('#EXTM3U\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=1920x1080\n'
              'variant.m3u8\n');
        case '/variant.m3u8':
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          request.response.write('#EXTM3U\n'
              '#EXT-X-TARGETDURATION:10\n'
              '#EXT-X-VERSION:3\n'
              '#EXTINF:10.0,\n'
              'seg.ts\n'
              '#EXT-X-ENDLIST\n');
        case '/seg.ts':
          request.response.headers.contentType = ContentType('video', 'mp2t');
          request.response.add(wrapped);
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    try {
      final relayUrl = await HlsRelay.instance.serve('$base/master.m3u8');
      expect(relayUrl, isNotNull, reason: 'serve() must not return null');
      final uri = Uri.parse(relayUrl!);
      expect(uri.host, '127.0.0.1');

      final client = HttpClient();
      try {
        // Master through the relay: variant URI points back at the relay.
        final masterText = await client
            .getUrl(uri)
            .then((r) => r.close())
            .then(utf8.decodeStream);
        expect(masterText, contains('127.0.0.1'));
        expect(masterText, contains('media.m3u8'));
        final variantUrl = masterText
            .split('\n')
            .firstWhere((l) => l.contains('media.m3u8'))
            .trim();
        expect(variantUrl, startsWith('http://127.0.0.1'));

        // Variant through the relay: segment URI points at the relay as
        // segment.ts.
        final variantText = await client
            .getUrl(Uri.parse(variantUrl))
            .then((r) => r.close())
            .then(utf8.decodeStream);
        expect(variantText, contains('segment.ts'));
        final segUrl = variantText
            .split('\n')
            .firstWhere((l) => l.contains('segment.ts'))
            .trim();
        expect(segUrl, startsWith('http://127.0.0.1'));

        // Segment through the relay: PNG wrapper stripped -> clean 0x47 TS.
        final segResp =
            await client.getUrl(Uri.parse(segUrl)).then((r) => r.close());
        final segChunks = await segResp.toList();
        final segBytes =
            Uint8List.fromList([for (final chunk in segChunks) ...chunk]);
        expect(segBytes.length, ts.length);
        expect(segBytes[0], 0x47);
        expect(segBytes[188], 0x47);
      } finally {
        client.close(force: true);
      }
    } finally {
      await HlsRelay.instance.dispose();
      await cdn.close(force: true);
    }
  });

  test('serve() returns null for a master with no media lines', () async {
    final cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${cdn.port}';
    cdn.listen((request) async {
      request.response.write('#EXTM3U\n#EXT-X-ERROR:not-a-playlist\n');
      await request.response.close();
    });
    try {
      final relayUrl = await HlsRelay.instance.serve('$base/bad.m3u8');
      expect(relayUrl, isNull);
    } finally {
      await HlsRelay.instance.dispose();
      await cdn.close(force: true);
    }
  });

  test('srtToVtt converts SRT timestamps, BOM and CRLF to WebVTT', () {
    const srt = '\uFEFF1\r\n'
        '00:00:01,000 --> 00:00:02,500\r\n'
        'Hello world\r\n'
        '\r\n'
        '2\r\n'
        '00:00:03,000 --> 00:00:04,000\r\n'
        'Second cue\r\n';
    final vtt = HlsRelay.srtToVtt(srt);
    expect(vtt, startsWith('WEBVTT'));
    expect(vtt, isNot(contains('\uFEFF')));
    expect(vtt, isNot(contains('\r')));
    expect(vtt, contains('00:00:01.000 --> 00:00:02.500'));
    expect(vtt, contains('00:00:03.000 --> 00:00:04.000'));
    expect(vtt, contains('Hello world'));
    expect(vtt, contains('Second cue'));
  });
  test(
      'master gets an injected HLS subtitle track pointing at the PLAYLIST (not a bare .vtt)',
      () async {
    // v1.3.45 lesson: the EXT-X-MEDIA URI must point at a subtitle PLAYLIST
    // (.m3u8) — a bare .vtt URI makes ffmpeg's hls demuxer try to parse the
    // WebVTT content AS a playlist, fail (`parse_playlist error Invalid
    // argument`), and reject the whole master (video never started). The
    // injected URI here must end with filmku-sub.m3u8.
    final cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${cdn.port}';
    cdn.listen((request) async {
      request.response.headers.contentType =
          ContentType('application', 'vnd.apple.mpegurl');
      request.response.write('#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=1920x1080\n'
          'variant.m3u8\n');
      await request.response.close();
    });
    try {
      final relayUrl = await HlsRelay.instance.serve('$base/master.m3u8');
      expect(relayUrl, isNotNull);
      // The player appends tmdbId to the relay URL (the injection trigger).
      final uri = Uri.parse(relayUrl!).replace(queryParameters: {
        ...Uri.parse(relayUrl).queryParameters,
        'tmdbId': '1339713',
      });
      final client = HttpClient();
      try {
        final masterText = await client
            .getUrl(uri)
            .then((r) => r.close())
            .then(utf8.decodeStream);
        expect(masterText, contains('#EXT-X-MEDIA:TYPE=SUBTITLES'));
        expect(masterText, contains('GROUP-ID="filmku"'));
        // CRITICAL: URI points at the PLAYLIST, not the .vtt segment.
        expect(masterText, contains('filmku-sub.m3u8?tmdbId=1339713'));
        expect(masterText, isNot(contains('filmku-sub.vtt?tmdbId')),
            reason: 'EXT-X-MEDIA URI must be a playlist, not a .vtt file');
        expect(masterText, contains('SUBTITLES="filmku"'));
        expect(masterText, contains('DEFAULT=NO'));
        // HLS spec: #EXTM3U MUST remain the very first line.
        expect(masterText.startsWith('#EXTM3U\n'), isTrue,
            reason: '#EXTM3U must stay the first line');
        final header = masterText.split('\n');
        expect(header[1], contains('#EXT-X-MEDIA:TYPE=SUBTITLES'));
      } finally {
        client.close(force: true);
      }
    } finally {
      await HlsRelay.instance.dispose();
      await cdn.close(force: true);
    }
  });

  test('master has NO injected subtitle track without tmdbId', () async {
    HlsRelay.instance
        .serveSubtitle(1339713, '1\n00:00:01,000 --> 00:00:02,000\nX\n');
    final cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${cdn.port}';
    cdn.listen((request) async {
      request.response.headers.contentType =
          ContentType('application', 'vnd.apple.mpegurl');
      request.response.write('#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=1000\n'
          'variant.m3u8\n');
      await request.response.close();
    });
    try {
      final relayUrl = await HlsRelay.instance.serve('$base/master.m3u8');
      expect(relayUrl, isNotNull);
      final client = HttpClient();
      try {
        // No tmdbId in the query — even though a slot IS registered, the
        // master must stay verbatim (injection is opt-in via the URL).
        final masterText = await client
            .getUrl(Uri.parse(relayUrl!))
            .then((r) => r.close())
            .then(utf8.decodeStream);
        expect(masterText, isNot(contains('#EXT-X-MEDIA:TYPE=SUBTITLES')));
        expect(masterText, isNot(contains('filmku-sub.m3u8')));
      } finally {
        client.close(force: true);
      }
    } finally {
      await HlsRelay.instance.dispose();
      await cdn.close(force: true);
    }
  });

  test('subtitle PLAYLIST route serves valid HLS with the .vtt segment',
      () async {
    const srt = '1\n00:00:01,000 --> 00:00:02,000\nSubtitle here\n';
    HlsRelay.instance.serveSubtitle(1339713, srt);
    final cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${cdn.port}';
    cdn.listen((request) async {
      request.response.write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\n'
          'variant.m3u8\n');
      await request.response.close();
    });
    try {
      final relayUrl = await HlsRelay.instance.serve('$base/master.m3u8');
      expect(relayUrl, isNotNull);
      final client = HttpClient();
      try {
        final port = Uri.parse(relayUrl!).port;
        final resp = await client
            .getUrl(Uri.parse(
                'http://127.0.0.1:$port/filmku-sub.m3u8?tmdbId=1339713'))
            .then((r) => r.close());
        expect(resp.statusCode, HttpStatus.ok);
        expect(resp.headers.contentType?.mimeType,
            'application/vnd.apple.mpegurl');
        final body = await utf8.decodeStream(resp);
        expect(body.startsWith('#EXTM3U\n'), isTrue);
        expect(body, contains('filmku-sub.vtt?tmdbId=1339713'));
        expect(body, contains('#EXT-X-ENDLIST'));
        // The segment (the .vtt route) is reachable and serves the SRT as
        // WebVTT.
        final vttResp = await client
            .getUrl(Uri.parse(
                'http://127.0.0.1:$port/filmku-sub.vtt?tmdbId=1339713'))
            .then((r) => r.close());
        expect(vttResp.statusCode, HttpStatus.ok);
        final vttBody = await utf8.decodeStream(vttResp);
        expect(vttBody, startsWith('WEBVTT'));
        expect(vttBody, contains('00:00:01.000 --> 00:00:02.000'));
        expect(vttBody, contains('Subtitle here'));
      } finally {
        client.close(force: true);
      }
    } finally {
      await HlsRelay.instance.dispose();
      await cdn.close(force: true);
    }
  });

  test('served subtitle slot is reachable as WebVTT via filmku-sub.vtt',
      () async {
    const srt = '1\n00:00:01,000 --> 00:00:02,000\nSubtitle here\n';
    HlsRelay.instance.serveSubtitle(1339713, srt);
    final cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${cdn.port}';
    cdn.listen((request) async {
      request.response.write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\n'
          'variant.m3u8\n');
      await request.response.close();
    });
    try {
      final relayUrl = await HlsRelay.instance.serve('$base/master.m3u8');
      expect(relayUrl, isNotNull);
      final client = HttpClient();
      try {
        final port = Uri.parse(relayUrl!).port;
        final resp = await client
            .getUrl(Uri.parse(
                'http://127.0.0.1:$port/filmku-sub.vtt?tmdbId=1339713'))
            .then((r) => r.close());
        expect(resp.statusCode, HttpStatus.ok);
        expect(resp.headers.contentType?.mimeType, 'text/vtt');
        final body = await utf8.decodeStream(resp);
        expect(body, startsWith('WEBVTT'));
        expect(body, contains('00:00:01.000 --> 00:00:02.000'));
        expect(body, contains('Subtitle here'));
      } finally {
        client.close(force: true);
      }
    } finally {
      await HlsRelay.instance.dispose();
      await cdn.close(force: true);
    }
  });
}
