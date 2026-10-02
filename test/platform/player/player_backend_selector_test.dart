/// 批次 C · C-11：播放器后端选择 + wire 线上值锁定。
///
/// 锁定桌面（Windows/macOS）libmpv 主后端口径（D6），以及
/// ChannelPlayer.open 传给原生插件的 `backend` 线上字符串
/// （Windows `player_plugin.cpp` 仅实现 libmpv，收到其他值返回
/// E_BACKEND_UNAVAILABLE，见 windows/runner/player_plugin.cpp）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/domain/entities/player/player.dart';
import 'package:vbox/platform/player/player_channel_bridge.dart';

void main() {
  group('PlayerBackendSelector.chainFor', () {
    test('windows → 仅 libmpv（C-11 主后端）', () {
      expect(
        PlayerBackendSelector.chainFor('windows'),
        const <PlayerBackend>[PlayerBackend.libmpv],
      );
    });

    test('macos → 仅 libmpv（与 Windows 同链，case 穿透）', () {
      expect(
        PlayerBackendSelector.chainFor('macos'),
        const <PlayerBackend>[PlayerBackend.libmpv],
      );
    });

    test('android → media3 主 + libVLC 回退', () {
      expect(
        PlayerBackendSelector.chainFor('android'),
        const <PlayerBackend>[PlayerBackend.media3, PlayerBackend.libVLC],
      );
    });

    test('ios → nativeiOS（不迁移占位）', () {
      expect(
        PlayerBackendSelector.chainFor('ios'),
        const <PlayerBackend>[PlayerBackend.nativeiOS],
      );
    });
  });

  group('backendWireValue（原生 open 参数）', () {
    test('libmpv → "libmpv"（player_plugin.cpp 唯一接受值）', () {
      expect(backendWireValue(PlayerBackend.libmpv), 'libmpv');
    });

    test('media3 / libVLC / nativeiOS 各自对齐 Android/iOS 侧', () {
      expect(backendWireValue(PlayerBackend.media3), 'media3');
      expect(backendWireValue(PlayerBackend.libVLC), 'libVLC');
      expect(backendWireValue(PlayerBackend.nativeiOS), 'nativeiOS');
    });
  });

  group('PlayerBackendSelector.needsFallback（A21.5 清单）', () {
    test('复杂封装 → 需全格式后端回退', () {
      for (final String ext in <String>[
        '.mkv', '.flv', '.ts', '.rmvb', '.avi', '.wmv', '.m2ts',
      ]) {
        expect(
          PlayerBackendSelector.needsFallback('https://x/a$ext'),
          isTrue,
          reason: '扩展名 $ext 应触发回退',
        );
      }
    });

    test('常规容器 → 不回退', () {
      expect(
        PlayerBackendSelector.needsFallback('https://x/a.mp4'),
        isFalse,
      );
      expect(
        PlayerBackendSelector.needsFallback('https://x/a.m3u8'),
        isFalse,
      );
    });
  });
}
