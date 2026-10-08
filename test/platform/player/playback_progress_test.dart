/// 第 5 批 · UI-F16：播放进度续播（守卫 + 存取）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vbox/platform/player/playback_progress.dart';

void main() {
  group('PlaybackProgressStore 判定（UI-F16）', () {
    test('恢复守卫：> 10s 才续播', () {
      expect(PlaybackProgressStore.shouldResume(10), isFalse);
      expect(PlaybackProgressStore.shouldResume(10.5), isTrue);
      expect(PlaybackProgressStore.shouldResume(0), isFalse);
    });

    test('保存守卫：> 5s 才落库', () {
      expect(PlaybackProgressStore.shouldSave(5), isFalse);
      expect(PlaybackProgressStore.shouldSave(5.5), isTrue);
    });

    test('看完判定：距结尾 < 15s', () {
      expect(PlaybackProgressStore.isNearEnd(990, 1000), isTrue);
      expect(PlaybackProgressStore.isNearEnd(980, 1000), isFalse);
      // 时长未知 → 不判为看完。
      expect(PlaybackProgressStore.isNearEnd(100, 0), isFalse);
    });

    test('键名按视频独立', () {
      expect(PlaybackProgressStore.keyOf('v123'), 'progress_v123');
    });
  });

  group('PlaybackProgressStore 存取（UI-F16）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('save / load 往返；空 vodId 直接忽略', () async {
      await PlaybackProgressStore.save('v1', 42.5);
      expect(await PlaybackProgressStore.load('v1'), 42.5);
      // 未记录 → 0
      expect(await PlaybackProgressStore.load('v2'), 0);
      // 空 id → 不读写
      await PlaybackProgressStore.save('', 10);
      expect(await PlaybackProgressStore.load(''), 0);
    });

    test('clear 移除记录', () async {
      await PlaybackProgressStore.save('v1', 42.5);
      await PlaybackProgressStore.clear('v1');
      expect(await PlaybackProgressStore.load('v1'), 0);
    });

    test('按视频独立互不影响', () async {
      await PlaybackProgressStore.save('v1', 30);
      await PlaybackProgressStore.save('v2', 60);
      expect(await PlaybackProgressStore.load('v1'), 30);
      expect(await PlaybackProgressStore.load('v2'), 60);
    });
  });
}
