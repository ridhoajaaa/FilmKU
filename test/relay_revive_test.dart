import 'package:flutter_test/flutter_test.dart';

import 'package:filmku/features/movies/data/datasources/stream_source_datasource.dart';
import 'package:filmku/features/movies/domain/entities/video_source.dart';
import 'package:filmku/features/movies/presentation/screens/player_screen.dart';

void main() {
  group('StreamSourceDataSource relay URL helpers', () {
    const relayUrl = 'http://127.0.0.1:41234/master.m3u8'
        '?src=https%3A%2F%2F2vcdn.skin%2Fstream%2Fab12%2Fcd34%2Fmaster.m3u8';

    test('detects a relay URL', () {
      expect(StreamSourceDataSource.isRelayUrl(relayUrl), isTrue);
    });

    test('extracts the original CDN URL from a relay URL', () {
      expect(
        StreamSourceDataSource.relaySourceOf(relayUrl),
        'https://2vcdn.skin/stream/ab12/cd34/master.m3u8',
      );
    });

    test('rejects plain CDN / signed URLs', () {
      expect(
        StreamSourceDataSource.isRelayUrl(
          'https://2vcdn.skin/stream/ab12/cd34/master.m3u8',
        ),
        isFalse,
      );
      expect(
        StreamSourceDataSource.isRelayUrl(
          'https://noir.suubmon.store/mp/resource/x.mp4?sign=abc&t=123',
        ),
        isFalse,
      );
    });

    test('relaySourceOf returns null for non-relay URLs', () {
      expect(
        StreamSourceDataSource.relaySourceOf(
          'https://2vcdn.skin/stream/ab12/cd34/master.m3u8',
        ),
        isNull,
      );
    });
  });

  group('PlayerScreen.reviveRelaySources', () {
    VideoSource plain() => const VideoSource(
          sourceId: 'vidlink',
          label: 'VidLink',
          videoUrl: 'https://noir.suubmon.store/mp/resource/x.mp4?sign=abc',
          embedUrl: 'https://vidlink.pro/movie/123',
          quality: 'Auto',
        );

    VideoSource relayed() => VideoSource(
          sourceId: 'two_embed_skin',
          label: '2Embed.skin',
          videoUrl: 'http://127.0.0.1:41000/master.m3u8'
              '?src=${Uri.encodeComponent('https://2vcdn.skin/stream/a/b/master.m3u8')}',
          embedUrl: 'https://www.2embed.skin/embed/movie/123',
          quality: 'Auto',
          subtitles: const [SubtitleTrack(label: 'Subs', url: 'x.vtt')],
        );

    test('non-relay sources pass through untouched (serve not called)',
        () async {
      var serveCalled = 0;
      final result = await PlayerScreen.reviveRelaySources(
        [plain()],
        serve: (_) async {
          serveCalled++;
          return 'http://127.0.0.1:9999/master.m3u8?src=x';
        },
      );
      expect(result.length, 1);
      expect(result.single.videoUrl, plain().videoUrl);
      expect(serveCalled, 0);
    });

    test('relay source is re-served with a fresh URL (fields preserved)',
        () async {
      final result = await PlayerScreen.reviveRelaySources(
        [relayed()],
        serve: (original) async {
          expect(
            original,
            'https://2vcdn.skin/stream/a/b/master.m3u8',
          );
          return 'http://127.0.0.1:55555/master.m3u8?src=$original';
        },
      );
      expect(result.length, 1);
      final revived = result.single;
      expect(
        revived.videoUrl,
        'http://127.0.0.1:55555/master.m3u8'
        '?src=https://2vcdn.skin/stream/a/b/master.m3u8',
      );
      // Everything else survives the re-serve.
      expect(revived.sourceId, 'two_embed_skin');
      expect(revived.label, '2Embed.skin');
      expect(revived.embedUrl, 'https://www.2embed.skin/embed/movie/123');
      expect(revived.subtitles.single.label, 'Subs');
    });

    test('relay source whose original can no longer be fetched is DROPPED',
        () async {
      final result = await PlayerScreen.reviveRelaySources(
        [relayed(), plain()],
        serve: (_) async => null, // relay bind failed → stale URL unusable
      );
      expect(result.length, 1);
      expect(result.single.sourceId, 'vidlink');
    });

    test('relay URL matching the LIVE relay port is kept (no re-serve)',
        () async {
      // First play: extraction served the URL a moment ago — the relay is
      // running on the SAME port, so re-serving would be a redundant fetch.
      // The port-match guard keeps the cached URL as-is.
      var serveCalled = 0;
      final result = await PlayerScreen.reviveRelaySources(
        [relayed()],
        serve: (_) async {
          serveCalled++;
          return 'http://127.0.0.1:9999/master.m3u8?src=x';
        },
        isStale: (_) => false, // port matches the live relay
      );
      expect(result.single.videoUrl, relayed().videoUrl);
      expect(serveCalled, 0);
    });
  });
}
