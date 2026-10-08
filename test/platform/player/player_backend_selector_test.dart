/// 批次 C · C-11：播放器后端选择 + wire 线上值锁定。
///
/// 锁定各端后端降级链口径（D6）与 MDK 统一内核接缝（M1），以及
/// ChannelPlayer.open 传给原生插件的 `backend` 线上字符串
/// （Windows `player_plugin.cpp` 仅实现 libmpv，收到其他值返回
/// E_BACKEND_UNAVAILABLE，见 windows/runner/player_plugin.cpp）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/domain/entities/player/player.dart';
import 'package:vbox/platform/player/player_channel_bridge.dart';

void main() {
  group('PlayerBackendSelector.chainFor', () {
    test('windows → libmpv 主 + MDK 次（M1：默认路径仍走 libmpv）', () {
      expect(
        PlayerBackendSelector.chainFor('windows'),
        const <PlayerBackend>[PlayerBackend.libmpv, PlayerBackend.mdk],
      );
    });

    test('macos → 与 Windows 同链，case 穿透', () {
      expect(
        PlayerBackendSelector.chainFor('macos'),
        const <PlayerBackend>[PlayerBackend.libmpv, PlayerBackend.mdk],
      );
    });

    test('android → media3 主 + MDK + libVLC 回退', () {
      expect(
        PlayerBackendSelector.chainFor('android'),
        const <PlayerBackend>[
          PlayerBackend.media3,
          PlayerBackend.mdk,
          PlayerBackend.libVLC,
        ],
      );
    });

    test('ios → nativeiOS（不迁移占位）', () {
      expect(
        PlayerBackendSelector.chainFor('ios'),
        const <PlayerBackend>[PlayerBackend.nativeiOS],
      );
    });

    test('链首即默认主后端（默认路径不经过 MDK）', () {
      expect(PlayerBackendSelector.chainFor('android').first,
          PlayerBackend.media3);
      expect(PlayerBackendSelector.chainFor('windows').first,
          PlayerBackend.libmpv);
    });
  });

  group('backendWireValue（原生 open 参数）', () {
    test('libmpv → "libmpv"（player_plugin.cpp 唯一接受值）', () {
      expect(backendWireValue(PlayerBackend.libmpv), 'libmpv');
    });

    test('mdk → "mdk"（M1：原生未接入前由降级链兜底）', () {
      expect(backendWireValue(PlayerBackend.mdk), 'mdk');
    });

    test('media3 / libVLC / nativeiOS 各自对齐 Android/iOS 侧', () {
      expect(backendWireValue(PlayerBackend.media3), 'media3');
      expect(backendWireValue(PlayerBackend.libVLC), 'libVLC');
      expect(backendWireValue(PlayerBackend.nativeiOS), 'nativeiOS');
    });
  });

  group('PlayerBackendMeta（M1 · MDK 元数据）', () {
    test('MDK 显示名 / 短名 / 系统 PiP 能力', () {
      expect(PlayerBackend.mdk.displayName, 'MDK（全格式）');
      expect(PlayerBackend.mdk.shortName, 'MDK');
      expect(PlayerBackend.mdk.supportsSystemPip, isFalse);
    });

    test('每个后端元数据非空（面板文案完整性）', () {
      for (final PlayerBackend b in PlayerBackend.values) {
        expect(b.displayName, isNotEmpty, reason: b.name);
        expect(b.shortName, isNotEmpty, reason: b.name);
      }
    });
  });

  group('PlayerBackendSelector.initialBackend（M1 · 初始后端选择）', () {
    const List<PlayerBackend> android = <PlayerBackend>[
      PlayerBackend.media3,
      PlayerBackend.mdk,
      PlayerBackend.libVLC,
    ];
    const List<PlayerBackend> desktop = <PlayerBackend>[
      PlayerBackend.libmpv,
      PlayerBackend.mdk,
    ];

    test('常规媒体 → 链首主后端（默认路径不经过 MDK）', () {
      expect(
        PlayerBackendSelector.initialBackend(
          chain: android,
          needsFullFormat: false,
        ),
        PlayerBackend.media3,
      );
      expect(
        PlayerBackendSelector.initialBackend(
          chain: desktop,
          needsFullFormat: false,
        ),
        PlayerBackend.libmpv,
      );
    });

    test('需全格式 → MDK 优先（统一内核）', () {
      expect(
        PlayerBackendSelector.initialBackend(
          chain: android,
          needsFullFormat: true,
        ),
        PlayerBackend.mdk,
      );
      expect(
        PlayerBackendSelector.initialBackend(
          chain: desktop,
          needsFullFormat: true,
        ),
        PlayerBackend.mdk,
      );
    });

    test('回退序：无 MDK → libVLC → libmpv → 链首', () {
      expect(
        PlayerBackendSelector.initialBackend(
          chain: const <PlayerBackend>[PlayerBackend.media3, PlayerBackend.libVLC],
          needsFullFormat: true,
        ),
        PlayerBackend.libVLC,
      );
      expect(
        PlayerBackendSelector.initialBackend(
          chain: const <PlayerBackend>[PlayerBackend.libmpv],
          needsFullFormat: true,
        ),
        PlayerBackend.libmpv,
      );
      expect(
        PlayerBackendSelector.initialBackend(
          chain: const <PlayerBackend>[PlayerBackend.media3],
          needsFullFormat: true,
        ),
        PlayerBackend.media3,
      );
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
