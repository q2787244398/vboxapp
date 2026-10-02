/// 批次 C · C-01：PlaybackRouteResolver 路由判定（纯 Dart）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/domain/entities/player/player.dart';
import 'package:vbox/platform/player/playback_route.dart';

void main() {
  group('PlaybackRouteResolver.resolve', () {
    test('直播流（isLive）→ live，即使扩展名像点播', () {
      const PlayerSource s = PlayerSource(
        url: 'https://x/live.m3u8',
        isLive: true,
      );
      expect(PlaybackRouteResolver.resolve(s), PlaybackRoute.live);
    });

    test('FLV 直播 → live', () {
      const PlayerSource s = PlayerSource(url: 'https://x/stream.flv');
      expect(PlaybackRouteResolver.resolve(s), PlaybackRoute.live);
    });

    test('点播 m3u8 → detail', () {
      const PlayerSource s = PlayerSource(url: 'https://x/movie.m3u8');
      expect(PlaybackRouteResolver.resolve(s), PlaybackRoute.detail);
    });

    test('mp4 / mkv 点播 → detail', () {
      expect(
        PlaybackRouteResolver.resolve(
          const PlayerSource(url: 'https://x/a.mp4'),
        ),
        PlaybackRoute.detail,
      );
      expect(
        PlaybackRouteResolver.resolve(
          const PlayerSource(url: 'https://x/a.mkv'),
        ),
        PlaybackRoute.detail,
      );
    });

    test('音频扩展名 → music', () {
      expect(
        PlaybackRouteResolver.resolve(
          const PlayerSource(url: 'https://x/song.mp3'),
        ),
        PlaybackRoute.music,
      );
      expect(
        PlaybackRouteResolver.resolve(
          const PlayerSource(url: 'https://x/podcast.flac'),
        ),
        PlaybackRoute.music,
      );
    });

    test('本地文件 → local', () {
      expect(
        PlaybackRouteResolver.resolve(
          const PlayerSource(url: 'file:///sdcard/video.mp4'),
        ),
        PlaybackRoute.local,
      );
      expect(
        PlaybackRouteResolver.resolve(
          const PlayerSource(url: '/home/u/video.mp4'),
        ),
        PlaybackRoute.local,
      );
      expect(
        PlaybackRouteResolver.resolve(
          const PlayerSource(url: r'C:\video\a.mp4'),
        ),
        PlaybackRoute.local,
      );
    });

    test('URL 大小写不敏感（.MP3 → music）', () {
      expect(
        PlaybackRouteResolver.resolve(
          const PlayerSource(url: 'https://x/SONG.MP3'),
        ),
        PlaybackRoute.music,
      );
    });
  });
}
