/// 批次 C · C-03：弹幕设置快照（默认 / copyWith / fromPlayback / normalized）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/platform/player/danmaku/danmaku_settings.dart';
import 'package:vbox/platform/player/playback_settings.dart';

void main() {
  group('DanmakuSettings', () {
    test('会话默认值（开 / 0.8 / 16px / 1.0，自定义源关）', () {
      expect(DanmakuSettings.defaults.enabled, isTrue);
      expect(DanmakuSettings.defaults.opacity, 0.8);
      expect(DanmakuSettings.defaults.fontSize, 16);
      expect(DanmakuSettings.defaults.area, 1.0);
      expect(DanmakuSettings.defaults.customSourceEnabled, isFalse);
      expect(DanmakuSettings.defaults.customSourceUrl, isEmpty);
    });

    test('copyWith 只改指定字段，其余保留', () {
      final DanmakuSettings s =
          DanmakuSettings.defaults.copyWith(opacity: 0.5, enabled: false);
      expect(s.opacity, 0.5);
      expect(s.enabled, isFalse);
      expect(s.fontSize, 16); // 未改
      expect(s.area, 1.0);
    });

    test('fromPlayback 取自定义弹幕源，会话参数保持默认', () {
      const PlaybackSettings p = PlaybackSettings(
        pipEnabled: true,
        backgroundPlay: false,
        autoPlayNext: true,
        longPressSpeed: 2.0,
        customDanmakuSourceEnabled: true,
        customDanmakuSourceUrl: 'http://x/dm.xml',
      );
      final DanmakuSettings s = DanmakuSettings.fromPlayback(p);
      expect(s.customSourceEnabled, isTrue);
      expect(s.customSourceUrl, 'http://x/dm.xml');
      expect(s.enabled, isTrue);
      expect(s.opacity, 0.8);
    });

    test('normalized 越界值 clamp 到合法区间', () {
      const DanmakuSettings s = DanmakuSettings(
        enabled: true,
        opacity: 3.0,
        fontSize: 100,
        area: 0.01,
        customSourceEnabled: false,
        customSourceUrl: '',
      );
      final DanmakuSettings n = s.normalized();
      expect(n.opacity, 1.0);
      expect(n.fontSize, 32);
      expect(n.area, 0.25);
    });

    test('normalized 未越界值保持不变', () {
      const DanmakuSettings s = DanmakuSettings(
        enabled: true,
        opacity: 0.5,
        fontSize: 18,
        area: 0.75,
        customSourceEnabled: false,
        customSourceUrl: '',
      );
      final DanmakuSettings n = s.normalized();
      expect(n.opacity, 0.5);
      expect(n.fontSize, 18);
      expect(n.area, 0.75);
    });

    test('toString 含关键字段', () {
      expect(
        DanmakuSettings.defaults.toString(),
        contains('DanmakuSettings'),
      );
      expect(DanmakuSettings.defaults.toString(), contains('en=true'));
    });
  });
}