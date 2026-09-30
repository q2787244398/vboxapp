/// 领域层单测：PlaybackDetail / PlaybackUrlParser（vod_play_from / vod_play_url 解析）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/domain/entities/playback/playback.dart';
import 'package:vbox/domain/entities/spider/site_config.dart';
import 'package:vbox/domain/entities/spider/spider_models.dart';

void main() {
  group('PlaybackUrlParser.parse', () {
    test('契约 §3.4：双线路多剧集拆分', () {
      final ParsedPlayUrl p = PlaybackUrlParser.parse(
        '线路1\$\$\$线路2',
        '第1集\$https://v.com/1.m3u8#第2集\$https://v.com/2.m3u8'
        '\$\$\$第1集\$https://v.com/3.m3u8',
      );
      expect(p.froms, <String>['线路1', '线路2']);
      expect(p.episodes.length, 3);
      expect(p.episodes[0].name, '第1集');
      expect(p.episodes[0].url, 'https://v.com/1.m3u8');
      expect(p.episodes[0].from, '线路1');
      expect(p.episodes[1].name, '第2集');
      expect(p.episodes[1].from, '线路1');
      expect(p.episodes[2].name, '第1集');
      expect(p.episodes[2].url, 'https://v.com/3.m3u8');
      expect(p.episodes[2].from, '线路2');
    });

    test('from 缺失/少于线路 → 线路序号回填', () {
      final ParsedPlayUrl p = PlaybackUrlParser.parse(
        null,
        '第1集\$https://v.com/1.m3u8\$\$\$第1集\$https://v.com/2.m3u8',
      );
      expect(p.froms, isEmpty);
      expect(p.episodes[0].from, '线路1');
      expect(p.episodes[1].from, '线路2');
    });

    test('容错：空地址过滤 / 无「\$」分隔的非法段跳过 / 空串返回空', () {
      final ParsedPlayUrl p = PlaybackUrlParser.parse(
        '',
        '第1集\$https://v.com/1.m3u8#垃圾段#第2集\$',
      );
      expect(p.episodes.length, 1);
      expect(p.episodes.single.name, '第1集');

      expect(PlaybackUrlParser.parse('', '').episodes, isEmpty);
      expect(PlaybackUrlParser.parse('', '   ').episodes, isEmpty);
      expect(PlaybackUrlParser.parse('', '第1集\$https://v.com/a.mp4')
          .episodes.single.url, 'https://v.com/a.mp4');
    });

    test('地址内含「\$」：取首个「\$」之后剩余拼接', () {
      final ParsedPlayUrl p = PlaybackUrlParser.parse(
        '',
        '第1集\$https://v.com/a.php?u=x\$y&z=1',
      );
      expect(p.episodes.single.url, 'https://v.com/a.php?u=x\$y&z=1');
    });

    test('兼容「\$\$」残余写法拆分线路', () {
      final ParsedPlayUrl p = PlaybackUrlParser.parse(
        '线A\$\$线B',
        '第1集\$https://v.com/1.m3u8\$\$第1集\$https://v.com/2.m3u8',
      );
      expect(p.episodes.length, 2);
      expect(p.episodes[0].from, '线A');
      expect(p.episodes[1].from, '线B');
    });
  });

  group('PlaybackUrlParser.looksDirectMedia', () {
    test('http(s) + 媒体扩展名 → 直链', () {
      for (final String url in <String>[
        'https://v.com/1.m3u8',
        'http://v.com/a.mp4?t=1',
        'https://cdn.com/x.mkv',
        'https://cdn.com/x.mp3',
      ]) {
        expect(PlaybackUrlParser.looksDirectMedia(url), isTrue, reason: url);
      }
    });

    test('页面地址 / 非 http → 非直链', () {
      expect(
        PlaybackUrlParser.looksDirectMedia('https://v.com/play/123'),
        isFalse,
      );
      expect(PlaybackUrlParser.looksDirectMedia('/local/path.mp4'), isFalse);
      expect(PlaybackUrlParser.looksDirectMedia(''), isFalse);
    });
  });

  group('PlaybackDetail.fromVod', () {
    const SiteConfig site = SiteConfig(
      key: 'y_csp1',
      name: '示例源',
      type: 3,
      api: 'https://cdn.example.com/x.js',
    );

    PlaybackDetail build({int initialIndex = 0}) => PlaybackDetail.fromVod(
          site: site,
          vod: VodItem.fromJson(<String, Object?>{
            'vod_id': '123',
            'vod_name': '示例片',
            'vod_pic': '',
            'vod_play_from': '线路1\$\$\$线路2',
            'vod_play_url': '第1集\$https://v.com/1.m3u8#第2集\$https://v.com/2.m3u8'
                '\$\$\$第1集\$https://v.com/3.m3u8',
          }),
          initialIndex: initialIndex,
        );

    test('解析出 froms + episodes，initialIndex 钳制到合法区间', () {
      final PlaybackDetail d = build(initialIndex: 99);
      expect(d.froms, <String>['线路1', '线路2']);
      expect(d.episodes.length, 3);
      expect(d.initialIndex, 2); // 钳制到最后一个
      expect(d.episodes[d.initialIndex].name, '第1集');
      expect(d.episodes[d.initialIndex].from, '线路2');
    });

    test('负数 / 空剧集 → 0', () {
      expect(build(initialIndex: -5).initialIndex, 0);
      final PlaybackDetail empty = PlaybackDetail.fromVod(
        site: site,
        vod: VodItem.fromJson(<String, Object?>{
          'vod_id': '1',
          'vod_name': '无剧集',
          'vod_pic': '',
        }),
        initialIndex: 7,
      );
      expect(empty.episodes, isEmpty);
      expect(empty.initialIndex, 0);
    });
  });
}
