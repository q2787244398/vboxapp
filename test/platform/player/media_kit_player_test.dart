/// G-02-A：MediaKitPlayer 控制转发 + 事件桥接（注入假 media_kit core，纯 Dart）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:vbox/domain/entities/player/player.dart';
import 'package:vbox/platform/player/media_kit_player.dart';

/// 假 media_kit 平台实现：记录控制调用，经其广播流推事件。
class _FakePlatform extends mk.PlatformPlayer {
  _FakePlatform() : super(configuration: const mk.PlayerConfiguration());

  final List<String> calls = <String>[];
  double? volume;
  double? rate;
  int? seekMs;
  bool opened = false;

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    opened = true;
    calls.add('open');
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seek(Duration duration) async {
    seekMs = duration.inMilliseconds;
    calls.add('seek');
  }

  @override
  Future<void> setVolume(double v) async {
    volume = v;
    calls.add('setVolume');
  }

  @override
  Future<void> setRate(double r) async {
    rate = r;
    calls.add('setRate');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await super.dispose();
  }

  // —— 事件注入（在子类内访问 @protected 广播控制器）——
  void emitPlaying(bool v) => playingController.add(v);
  void emitBuffering(bool v) => bufferingController.add(v);
  void emitCompleted(bool v) => completedController.add(v);
  void emitPosition(Duration d) => positionController.add(d);
  void emitDuration(Duration d) => durationController.add(d);
  void emitBuffer(Duration d) => bufferController.add(d);
  void emitWidth(int? w) => widthController.add(w);
  void emitHeight(int? h) => heightController.add(h);
  void emitError(String m) => errorController.add(m);
  void emitLog(mk.PlayerLog log) => logController.add(log);
}

/// 以假 core / 假纹理通知驱动构建 [MediaKitPlayer]。
///
/// 始终注入 `ValueNotifier<int?>`（缺省为 null），避免未提供 [textureId] 时真实
/// 构造 media_kit_video 的 `VideoController`（其构造阶段需 `WidgetsBinding`，
/// 在纯 `test()` 下会抛未处理 async 异常）。
MediaKitPlayer _build({_FakePlatform? platform, ValueListenable<int?>? textureId}) {
  platform ??= _FakePlatform();
  return MediaKitPlayer(
    backend: PlayerBackend.mediaKit,
    core: mk.Player(platformPlayer: platform),
    textureId: textureId ?? ValueNotifier<int?>(null),
  );
}

void main() {
  group('MediaKitPlayer 控制面', () {
    test('play/pause/seekTo/setVolume/setSpeed/dispose 依次转发', () async {
      final _FakePlatform platform = _FakePlatform();
      final MediaKitPlayer p = _build(platform: platform);
      await p.play();
      await p.pause();
      await p.seekTo(120000);
      await p.setVolume(0.5);
      await p.setSpeed(1.5);
      await p.dispose();
      expect(
        platform.calls,
        <String>['play', 'pause', 'seek', 'setVolume', 'setRate', 'dispose'],
      );
      expect(platform.seekMs, 120000);
      expect(platform.volume, 50.0);
      expect(platform.rate, 1.5);
    });

    test('setVolume：0..1 契约换算为 media_kit 0..100', () async {
      final _FakePlatform platform = _FakePlatform();
      final MediaKitPlayer p = _build(platform: platform);
      await p.setVolume(0.0);
      expect(platform.volume, 0.0);
      await p.setVolume(1.0);
      expect(platform.volume, 100.0);
      await p.setVolume(0.33);
      expect(platform.volume, closeTo(33.0, 0.001));
      await p.dispose();
    });

    test('open：转发并写 isLive；假 core 非 NativePlayer 时跳过 setProperty', () async {
      final _FakePlatform platform = _FakePlatform();
      final MediaKitPlayer p = _build(platform: platform);
      await p.open(const PlayerSource(url: 'https://x/live.m3u8', isLive: true));
      expect(platform.opened, true);
      expect(platform.calls, contains('open'));
      await p.dispose();
    });

    test('availableBackends 收敛为单元素链', () {
      final MediaKitPlayer p = _build();
      expect(p.availableBackends, <PlayerBackend>[PlayerBackend.mediaKit]);
    });
  });

  group('MediaKitPlayer 事件面', () {
    test('playing/buffering/completed → onStateChanged', () async {
      final _FakePlatform platform = _FakePlatform();
      final MediaKitPlayer p = _build(platform: platform);
      final List<PlayerState> states = <PlayerState>[];
      p.onStateChanged = states.add;
      platform.emitPlaying(true);
      platform.emitPlaying(false);
      platform.emitBuffering(true);
      platform.emitCompleted(true);
      await Future<void>.delayed(Duration.zero);
      expect(states, containsAll(<PlayerState>[
        PlayerState.playing,
        PlayerState.paused,
        PlayerState.buffering,
        PlayerState.ended,
      ]));
      await p.dispose();
    });

    test('position/duration/buffer → onProgress 合并（含 isLive）', () async {
      final _FakePlatform platform = _FakePlatform();
      final MediaKitPlayer p = _build(platform: platform);
      final List<PlaybackProgress> progress = <PlaybackProgress>[];
      p.onProgress = progress.add;
      await p.open(const PlayerSource(url: 'https://x/a.mp4', isLive: false));
      platform.emitDuration(const Duration(seconds: 60));
      platform.emitBuffer(const Duration(seconds: 45));
      platform.emitPosition(const Duration(seconds: 30));
      await Future<void>.delayed(Duration.zero);
      expect(progress, isNotEmpty);
      final PlaybackProgress last = progress.last;
      expect(last.positionMs, 30000);
      expect(last.durationMs, 60000);
      expect(last.bufferedMs, 45000);
      expect(last.isLive, false);
      await p.dispose();
    });

    test('width/height → onVideoSize；error → onError(fatal)', () async {
      final _FakePlatform platform = _FakePlatform();
      final MediaKitPlayer p = _build(platform: platform);
      int? w;
      int? h;
      p.onVideoSize = (int width, int height) {
        w = width;
        h = height;
      };
      String? message;
      bool? wasFatal;
      p.onError = (String m, {required bool fatal}) {
        message = m;
        wasFatal = fatal;
      };
      platform.emitWidth(1920);
      platform.emitHeight(1080);
      platform.emitError('解码失败');
      await Future<void>.delayed(Duration.zero);
      expect(w, 1920);
      expect(h, 1080);
      expect(message, '解码失败');
      expect(wasFatal, true);
      await p.dispose();
    });

    test('log → 按级别分派到 AppLog（不抛异常）', () async {
      final _FakePlatform platform = _FakePlatform();
      final MediaKitPlayer p = _build(platform: platform);
      platform.emitLog(const mk.PlayerLog(prefix: 'mpv', level: 'error', text: 'boom'));
      platform.emitLog(const mk.PlayerLog(prefix: 'mpv', level: 'warn', text: 'hmm'));
      platform.emitLog(const mk.PlayerLog(prefix: 'mpv', level: 'debug', text: 'dbg'));
      platform.emitLog(const mk.PlayerLog(prefix: 'mpv', level: 'info', text: 'ok'));
      await Future<void>.delayed(Duration.zero);
      // 仅验证 _log 分派不抛异常。
      await p.dispose();
    });
  });

  group('MediaKitPlayer 纹理面', () {
    test('textureId 取自注入的纹理通知；变化后触发 onTextureReady', () async {
      final ValueNotifier<int?> id = ValueNotifier<int?>(null);
      final MediaKitPlayer p = _build(textureId: id);
      expect(p.textureId, isNull);
      int? ready;
      p.onTextureReady = (int textureId) => ready = textureId;
      id.value = 7;
      await Future<void>.delayed(Duration.zero);
      expect(p.textureId, 7);
      expect(ready, 7);
      await p.dispose();
    });

    test('负句柄 / null 不触发 onTextureReady', () async {
      final ValueNotifier<int?> id = ValueNotifier<int?>(null);
      final MediaKitPlayer p = _build(textureId: id);
      int? ready;
      p.onTextureReady = (int textureId) => ready = textureId;
      id.value = -1;
      await Future<void>.delayed(Duration.zero);
      expect(ready, isNull);
      await p.dispose();
    });
  });
}