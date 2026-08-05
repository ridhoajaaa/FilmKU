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
        final segBytes = Uint8List.fromList(
            [for (final chunk in segChunks) ...chunk]);
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
}
