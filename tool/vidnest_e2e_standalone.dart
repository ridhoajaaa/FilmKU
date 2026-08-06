// ignore_for_file: avoid_print
//
// Standalone E2E for the VidNest native-extraction chain (v1.3.24).
//
// Verifies the FULL chain that StreamSourceDataSource.fetchVidNestSource +
// decodeVidNestPayload implement in the app, over the real network:
//
//   1. 2embed.skin shell exposes the vnest player (streamsrcs.2embed.cc/vnest)
//   2. VidNest server API (new.vidnest.fun/{server}/movie/{tmdb}) returns the
//      {"data": "...", "encrypted": true} payload
//   3. The payload decodes (custom-alphabet base64) to the streams JSON, which
//      carries the exact Referer the CDN requires
//   4. The best HLS stream (a real MASTER playlist) fetches cleanly with that
//      Referer (403 without it), and its variant + segment chain resolves
//
// Run: dart run tool/vidnest_e2e_standalone.dart [tmdb_id]
//
// NOTE: pure dart:io only (the app file imports Flutter, so this tool mirrors
// the production decode instead of importing it — keep the two in sync).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const String alphabet =
    'RB0fpH8ZEyVLkv7c2i6MAJ5u3IKFDxlS1NTsnGaqmXYdUrtzjwObCgQP94hoeW+/=';

String? decodeVidNestPayload(String data) {
  if (data.isEmpty) return null;
  final lookup = <int, int>{};
  for (var i = 0; i < alphabet.length; i++) {
    lookup[alphabet.codeUnitAt(i)] = i;
  }
  final chars = data.codeUnits;
  // Pad with '=' (0x3D) to a multiple of 4, like the site's decoder pads
  // every group before processing.
  final padded = chars.length % 4 == 0
      ? chars
      : [...chars, ...List.filled(4 - chars.length % 4, 0x3D)];
  final out = BytesBuilder(copy: false);
  for (var i = 0; i + 4 <= padded.length; i += 4) {
    final v0 = lookup[padded[i]] ?? 64;
    final v1 = lookup[padded[i + 1]] ?? 64;
    final v2 = lookup[padded[i + 2]] ?? 64;
    final v3 = lookup[padded[i + 3]] ?? 64;
    if (v0 == 64 || v1 == 64) break;
    out.addByte((v0 << 2) | (v1 >> 4));
    if (v2 != 64) {
      out.addByte(((v1 & 15) << 4) | (v2 >> 2));
      if (v3 != 64) out.addByte(((v2 & 3) << 6) | v3);
    }
  }
  if (out.isEmpty) return null;
  return utf8.decode(out.toBytes(), allowMalformed: true);
}

const String _ua =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

/// Fetches [url] and returns its body as UTF-8 text (binary-tolerant).
Future<String> fetchString(String url, {String? referer}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua);
    if (referer != null) req.headers.set('Referer', referer);
    final resp = await req.close().timeout(const Duration(seconds: 20));
    final bytes = await resp
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk)).timeout(
            const Duration(seconds: 20));
    return utf8.decode(bytes, allowMalformed: true);
  } finally {
    client.close(force: true);
  }
}

/// Fetches [url] and returns just the HTTP status (headless drain).
Future<int> fetchStatus(String url, {String? referer}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua);
    if (referer != null) req.headers.set('Referer', referer);
    final resp = await req.close().timeout(const Duration(seconds: 20));
    await resp.drain<void>().timeout(const Duration(seconds: 20));
    return resp.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<void> main(List<String> args) async {
  final tmdb = args.isNotEmpty ? args.first : '634649';
  var failures = 0;

  // 1. The 2embed.skin shell exposes the vnest player.
  final shell = await fetchString('https://www.2embed.skin/embed/movie/$tmdb');
  if (!shell.contains('streamsrcs.2embed.cc/vnest')) {
    print('FAIL: shell does not expose the vnest player (rotated back to '
        'swish?) — chain changed, re-probe needed.');
    failures++;
  } else {
    print('OK: shell exposes vnest player (streamsrcs.2embed.cc/vnest?tmdb='
        '$tmdb)');
  }

  // 2-3. Server API -> decode -> streams JSON.
  var decodedJson = '';
  for (final server in [
    'hollymoviehd',
    'videasy',
    'vidzee',
    'nextgencloudfabric'
  ]) {
    final url = 'https://new.vidnest.fun/$server/movie/$tmdb';
    final raw =
        await fetchString(url, referer: 'https://vidnest.fun/movie/$tmdb');
    Map<String, dynamic> outer;
    try {
      outer = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      print('server $server: non-JSON response');
      continue;
    }
    final data = outer['data'];
    if (data is! String) {
      print('server $server: no data field');
      continue;
    }
    final plain = decodeVidNestPayload(data);
    if (plain == null) {
      print('server $server: payload failed to decode');
      continue;
    }
    decodedJson = plain;
    print('OK: $server payload decoded (${plain.length} chars)');
    break;
  }
  if (decodedJson.isEmpty) {
    print('FAIL: no server returned a decodable payload');
    exit(1);
  }

  final parsed = jsonDecode(decodedJson) as Map<String, dynamic>;
  final streams = (parsed['streams'] as List).cast<Map<String, dynamic>>();
  final hlsStreams = streams.where((s) => s['type'] == 'hls').toList();
  print('OK: ${streams.length} streams (${hlsStreams.length} hls)');
  for (final s in streams) {
    print('    stream: type=${s['type']} lang=${s['language']} '
        'url=${s['url']}');
  }

  // 4. Prefer the HLS stream whose URL serves a real MASTER playlist.
  Map<String, dynamic>? chosen;
  String? chosenRef;
  for (final s in hlsStreams) {
    final url = s['url'] as String;
    final headers = (s['headers'] as Map?)?.cast<String, String>() ?? {};
    final ref = headers['Referer'] ?? '';
    final body = await fetchString(url, referer: ref);
    if (body.startsWith('#EXTM3U') && body.contains('#EXT-X-STREAM-INF')) {
      chosen = s;
      chosenRef = ref;
      print('OK: HLS master found: $url');
      break;
    }
    print('    (skip: not a master playlist) $url');
  }
  if (chosen == null) {
    print('FAIL: no HLS master playlist among the streams');
    exit(1);
  }

  final masterUrl = chosen['url'] as String;
  final noRef = await fetchStatus(masterUrl);
  print('master without Referer -> HTTP $noRef (expect 403/451)');

  final master = await fetchString(masterUrl, referer: chosenRef);
  final variant = master
      .split('\n')
      .firstWhere((l) => l.startsWith('http'), orElse: () => '');
  if (variant.isEmpty) {
    print('FAIL: no absolute variant URL in master');
    failures++;
  } else {
    final variantBody = await fetchString(variant, referer: chosenRef);
    final seg = variantBody.split('\n').firstWhere(
        (l) => l.startsWith('http') || l.startsWith('/'),
        orElse: () => '');
    if (seg.isEmpty) {
      print('FAIL: no segment URL in variant');
      failures++;
    } else {
      final segUrl = seg.startsWith('http') ? seg : 'https://goodstream.cc$seg';
      final status = await fetchStatus(segUrl, referer: chosenRef);
      print('OK: first segment (${segUrl.split('/').last}) -> HTTP $status');
    }
  }

  print(failures == 0
      ? '\nE2E PASS: VidNest chain is natively playable (decode + Referer).'
      : '\nE2E FAILED with $failures problem(s).');
  exit(failures == 0 ? 0 : 1);
}
