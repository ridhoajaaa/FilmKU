// ignore_for_file: avoid_print
//
// Standalone E2E for the 2vcdn direct-extraction + HLS-relay pipeline
// (pure dart:io + dio — no Flutter imports, so `dart run` compiles it alone).
//
// Usage:
//   dart run tool/relay_e2e_standalone.dart 969681
//
// Extracts the direct 2vcdn .m3u8 (Dean-Edwards packer, radix 36), serves it
// through a local relay that strips the fake-PNG wrapper from segments, and
// prints the relay URL. While it runs, verify with:
//   mpv http://127.0.0.1:{port}/master.m3u8?src=...
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

final dio = Dio(BaseOptions(
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
));

Future<String> fetchString(String url) async {
  final r = await dio.get<List<int>>(url);
  return utf8.decode(r.data ?? const [], allowMalformed: true);
}

String jsUnescape(String s) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final ch = s[i];
    if (ch == r'\' && i + 1 < s.length) {
      final nxt = s[i + 1];
      if (nxt == r'\') {
        out.write(r'\');
        i += 2;
      } else if (nxt == "'") {
        out.write("'");
        i += 2;
      } else if (nxt == '"') {
        out.write('"');
        i += 2;
      } else if (nxt == 'n') {
        out.write('\n');
        i += 2;
      } else if (nxt == 't') {
        out.write('\t');
        i += 2;
      } else if (nxt == 'r') {
        out.write('\r');
        i += 2;
      } else if (nxt == 'x' && i + 3 < s.length) {
        final code = int.tryParse(s.substring(i + 2, i + 4), radix: 16);
        out.write(String.fromCharCode(code ?? 0x3F));
        i += 4;
      } else if (nxt == 'u' && i + 5 < s.length) {
        final code = int.tryParse(s.substring(i + 2, i + 6), radix: 16);
        out.write(String.fromCharCode(code ?? 0x3F));
        i += 6;
      } else {
        out.write(nxt);
        i += 2;
      }
    } else {
      out.write(ch);
      i++;
    }
  }
  return out.toString();
}

String radixToBase(int num, int radix) {
  const digits =
      '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  if (num == 0) return '0';
  final out = StringBuffer();
  var n = num;
  while (n > 0) {
    out.write(digits[n % radix]);
    n ~/= radix;
  }
  return out.toString().split('').reversed.join();
}

String? unpackDeanEdwards(String packedBlock) {
  // Mirrors the app's robust parser (reviewer fix 2026-08): locate the key
  // array first, then radix/count, then slice the payload with lastIndexOf
  // (never a non-greedy .*? which a payload containing \',<digits>,<digits>,'
  // can truncate early), then strip the payload's wrapping quotes.
  final keysM = RegExp(r"'([^']*)'\.split\('\|'\)\)", dotAll: true)
      .firstMatch(packedBlock);
  if (keysM == null) return null;
  final keysStr = keysM.group(1)!;
  final metaM = RegExp(
    r",(\d+),(\d+),'" + RegExp.escape(keysStr) + r"'\.split",
  ).firstMatch(packedBlock);
  if (metaM == null) return null;
  final radix = int.tryParse(metaM.group(1)!) ?? 36;
  final count = int.tryParse(metaM.group(2)!) ?? 0;
  const open = 'return p}(';
  final openIdx = packedBlock.indexOf(open);
  // Boundary is `,radix,count,'keys'` — NO quote after the first comma.
  final boundary = ",$radix,$count,'$keysStr'";
  final bodyEnd = packedBlock.lastIndexOf(boundary);
  if (openIdx < 0 || bodyEnd <= openIdx + open.length) return null;
  var body = jsUnescape(packedBlock.substring(openIdx + open.length, bodyEnd));
  if (body.startsWith("'") && body.endsWith("'")) {
    body = body.substring(1, body.length - 1);
  }
  var keys = keysStr.split('|');
  while (keys.length < count) {
    keys = [...keys, ''];
  }
  for (var c = count - 1; c >= 0; c--) {
    if (c >= keys.length) continue;
    final k = keys[c];
    if (k.isEmpty) continue;
    final token = radixToBase(c, radix);
    final pattern =
        RegExp('(?<![A-Za-z0-9_])${RegExp.escape(token)}(?![A-Za-z0-9_])');
    body = body.replaceAll(pattern, k);
  }
  return body;
}

String? streamUrlFromPage(String pageHtml) {
  final start = pageHtml.indexOf('eval(function(p,a,c,k,e,d)');
  if (start < 0) return null;
  final unpacked = unpackDeanEdwards(pageHtml.substring(start));
  if (unpacked == null) return null;
  final m =
      RegExp(r'(/stream/[A-Za-z0-9_/-]+/master[.]m3u8)').firstMatch(unpacked);
  return m == null ? null : 'https://2vcdn.skin${m.group(1)}';
}

String? resolveSid(String shellHtml) {
  final m = RegExp(
    r'data-src="[^"]*streamsrcs[.]2embed[.]cc/swish[?]id=([a-zA-Z0-9_-]+)',
    caseSensitive: false,
  ).firstMatch(shellHtml);
  return m?.group(1);
}

Future<String?> extractDirect(String tmdbId) async {
  final shell =
      await fetchString('https://www.2embed.skin/embed/movie/$tmdbId');
  final sid = resolveSid(shell);
  if (sid == null || sid.isEmpty) return null;
  final playerPage = await fetchString('https://2vcdn.skin/e/$sid');
  return streamUrlFromPage(playerPage);
}

const pngSig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

Uint8List stripPngWrapper(Uint8List bytes) {
  if (bytes.length < 188) return bytes;
  if (bytes.length >= 8) {
    var isPng = true;
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != pngSig[i]) {
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
    }
  }
  return bytes;
}

Future<void> main(List<String> args) async {
  final tmdbId = args.isNotEmpty ? args[0] : '969681';
  print('=== E2E: tmdb=$tmdbId ===');

  final direct = await extractDirect(tmdbId);
  print('direct: $direct');
  if (direct == null) {
    print('FAILED: no direct stream');
    return;
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  server.listen((request) async {
    try {
      final src = request.uri.queryParameters['src'];
      if (src == null) {
        request.response.statusCode = 400;
        await request.response.close();
        return;
      }
      if (request.uri.path.endsWith('.m3u8')) {
        final body = await fetchString(src);
        final base = Uri.parse(src);
        final out = <String>[];
        final uriAttr = RegExp('URI="([^"]*)"');
        for (final rawLine in body.split('\n')) {
          final line = rawLine.trimRight();
          if (line.isEmpty) {
            out.add(rawLine);
            continue;
          }
          if (line.startsWith('#')) {
            out.add(line.replaceAllMapped(uriAttr, (m) {
              final ref = m.group(1)!;
              final resolved =
                  ref.startsWith('http') ? ref : base.resolve(ref).toString();
              final p = resolved.toLowerCase().endsWith('.m3u8')
                  ? 'media.m3u8'
                  : 'segment.ts';
              return 'URI="http://127.0.0.1:$port/$p'
                  '?src=${Uri.encodeComponent(resolved)}"';
            }));
            continue;
          }
          final resolved =
              line.startsWith('http') ? line : base.resolve(line).toString();
          final p = resolved.toLowerCase().endsWith('.m3u8')
              ? 'media.m3u8'
              : 'segment.ts';
          out.add('http://127.0.0.1:$port/$p'
              '?src=${Uri.encodeComponent(resolved)}');
        }
        request.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        request.response.add(utf8.encode(out.join('\n')));
      } else {
        final raw = await dio
            .get<List<int>>(src,
                options: Options(responseType: ResponseType.bytes))
            .then((r) => r.data ?? const <int>[]);
        final ts = stripPngWrapper(Uint8List.fromList(raw));
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.add(ts);
      }
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = 502;
        await request.response.close();
      } catch (_) {}
    }
  });

  final relayUrl = 'http://127.0.0.1:$port/master.m3u8'
      '?src=${Uri.encodeComponent(direct)}';
  print('relayUrl: $relayUrl');

  final master = await fetchString(relayUrl);
  final uris = master.split('\n').where((l) => l.startsWith('http')).toList();
  print('master via relay: ${master.length} chars, uris=${uris.length}');
  if (uris.isEmpty) {
    print('FAILED: master has no uris');
    await server.close(force: true);
    return;
  }
  print('first uri: ${uris.first}');

  final variant = await fetchString(uris.first);
  final segUris =
      variant.split('\n').where((l) => l.startsWith('http')).toList();
  print('variant via relay: ${variant.length} chars, segs=${segUris.length}');
  if (segUris.isEmpty) {
    print('FAILED: no segment uris');
    await server.close(force: true);
    return;
  }
  final seg = await dio
      .get<List<int>>(segUris.first,
          options: Options(responseType: ResponseType.bytes))
      .then((r) => r.data ?? const <int>[]);
  final bytes = Uint8List.fromList(seg);
  print('segment via relay: ${bytes.length} bytes, '
      'first8=${bytes.take(8).toList()}');
  final syncOk = bytes.length >= 189 && bytes[0] == 0x47 && bytes[188] == 0x47;
  print('CLEAN TS: syncOk=$syncOk');

  print('=== READY: $relayUrl ===');
  if (syncOk) {
    stdout.writeln('MPV_PLAY=$relayUrl');
    // Keep the server up so mpv can be pointed at the URL from another shell.
    await Future<void>.delayed(const Duration(hours: 2));
  } else {
    await server.close(force: true);
  }
}
