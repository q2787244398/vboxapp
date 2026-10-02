/// 批次 C · C-02/C-04：播放器控制层视图状态容器（派生值 / 面板互斥 / 回调上抛）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/domain/entities/player/player.dart';
import 'package:vbox/domain/entities/playback/playback_detail.dart';
import 'package:vbox/presentation/ui_mode/ui_mode.dart';
import 'package:vbox/presentation/widgets/player/player_controls_controller.dart';

void main() {
  group('派生值', () {
    test('progress 直播 / 未知时长恒 0', () {
      final PlayerControlsController c = PlayerControlsController(
        isLive: true,
        positionMs: 5000,
        durationMs: 10000,
      );
      expect(c.progress, 0);
      c.isLive = false;
      c.durationMs = 0;
      expect(c.progress, 0);
    });

    test('progress 正常比例', () {
      final PlayerControlsController c = PlayerControlsController(
        positionMs: 5000,
        durationMs: 10000,
      );
      expect(c.progress, 0.5);
    });

    test('buffered 直播恒 0', () {
      final PlayerControlsController c = PlayerControlsController(
        isLive: true,
        bufferedMs: 5000,
        durationMs: 10000,
      );
      expect(c.buffered, 0);
    });

    test('speedDisplayText 尾零裁剪', () {
      expect(PlayerControlsController(speed: 1.0).speedDisplayText, '1x');
      expect(PlayerControlsController(speed: 1.25).speedDisplayText, '1.25x');
      expect(PlayerControlsController(speed: 1.5).speedDisplayText, '1.5x');
      expect(PlayerControlsController(speed: 2.0).speedDisplayText, '2x');
      expect(PlayerControlsController(speed: 0.75).speedDisplayText, '0.75x');
    });

    test('qualityDisplayText 空回默认 / 越界钳制', () {
      expect(PlayerControlsController().qualityDisplayText, '默认');
      final PlayerControlsController c = PlayerControlsController(
        qualities: const <String>['标清', '高清', '蓝光'],
        selectedQuality: 1,
      );
      expect(c.qualityDisplayText, '高清');
      c.selectedQuality = 99;
      expect(c.qualityDisplayText, '蓝光'); // clamp 到末尾
    });

    test('backendDisplayText 四后端映射', () {
      expect(PlayerControlsController().backendDisplayText, '内核');
      expect(
        PlayerControlsController(currentBackend: PlayerBackend.media3)
            .backendDisplayText,
        'Media3',
      );
      expect(
        PlayerControlsController(currentBackend: PlayerBackend.libVLC)
            .backendDisplayText,
        'VLC',
      );
      expect(
        PlayerControlsController(currentBackend: PlayerBackend.libmpv)
            .backendDisplayText,
        'MPV',
      );
      expect(
        PlayerControlsController(currentBackend: PlayerBackend.nativeiOS)
            .backendDisplayText,
        '原生',
      );
    });

    test('positionText / durationText 时间格式', () {
      expect(PlayerControlsController(positionMs: 0).positionText, '00:00');
      expect(PlayerControlsController(positionMs: 61000).positionText, '01:01');
      expect(
        PlayerControlsController(positionMs: 3661000).positionText,
        '01:01:01',
      );
      expect(PlayerControlsController(durationMs: 0).durationText, '--:--');
      expect(PlayerControlsController(durationMs: 60000).durationText, '01:00');
    });

    test('hasPrevEpisode / hasNextEpisode 边界', () {
      const List<PlaybackEpisode> eps = <PlaybackEpisode>[
        PlaybackEpisode(name: '第1集', url: 'http://x/1'),
        PlaybackEpisode(name: '第2集', url: 'http://x/2'),
        PlaybackEpisode(name: '第3集', url: 'http://x/3'),
      ];
      final PlayerControlsController c =
          PlayerControlsController(episodes: eps, currentEpisodeIndex: 0);
      expect(c.hasPrevEpisode, isFalse);
      expect(c.hasNextEpisode, isTrue);

      c.currentEpisodeIndex = 1;
      expect(c.hasPrevEpisode, isTrue);
      expect(c.hasNextEpisode, isTrue);

      c.currentEpisodeIndex = 2;
      expect(c.hasPrevEpisode, isTrue);
      expect(c.hasNextEpisode, isFalse);
    });

    test('hasQuality / hasBackend', () {
      expect(PlayerControlsController().hasQuality, isFalse);
      expect(PlayerControlsController().hasBackend, isFalse);
      expect(
        PlayerControlsController(qualities: const <String>['x']).hasQuality,
        isTrue,
      );
      expect(
        PlayerControlsController(backends: const <PlayerBackend>[PlayerBackend.media3])
            .hasBackend,
        isTrue,
      );
    });
  });

  group('状态更新', () {
    test('updateProgress 更新并通知（保留可选未传字段）', () {
      final PlayerControlsController c = PlayerControlsController(bufferedMs: 100);
      int notified = 0;
      c.addListener(() => notified++);
      c.updateProgress(positionMs: 1000, durationMs: 2000, bufferedMs: 1500);
      expect(c.positionMs, 1000);
      expect(c.durationMs, 2000);
      expect(c.bufferedMs, 1500);
      expect(c.isLive, isFalse);
      c.updateProgress(positionMs: 2000, durationMs: 2000);
      expect(c.bufferedMs, 1500); // 未传 buffered 保留
      expect(notified, 2);
    });

    test('updatePlaying 无变化不通知', () {
      final PlayerControlsController c = PlayerControlsController();
      int notified = 0;
      c.addListener(() => notified++);
      c.updatePlaying(false); // 已是 false
      expect(notified, 0);
      c.updatePlaying(true);
      expect(notified, 1);
      expect(c.isPlaying, isTrue);
    });

    test('setForm 无变化不通知', () {
      final PlayerControlsController c = PlayerControlsController();
      int notified = 0;
      c.addListener(() => notified++);
      c.setForm(UiForm.portrait); // 已是 portrait
      expect(notified, 0);
      c.setForm(UiForm.landscape);
      expect(notified, 1);
      expect(c.form, UiForm.landscape);
    });
  });

  group('选择动作', () {
    test('selectEpisode 合法索引回调 + 关闭面板', () {
      const List<PlaybackEpisode> eps = <PlaybackEpisode>[
        PlaybackEpisode(name: '1', url: 'u1'),
        PlaybackEpisode(name: '2', url: 'u2'),
      ];
      int? selected;
      final PlayerControlsController c = PlayerControlsController(episodes: eps);
      c.onSelectEpisode = (int i) => selected = i;
      c.openEpisodePicker();
      c.selectEpisode(1);
      expect(selected, 1);
      expect(c.currentEpisodeIndex, 1);
      expect(c.showEpisodePicker, isFalse);
    });

    test('selectEpisode 越界忽略', () {
      const List<PlaybackEpisode> eps = <PlaybackEpisode>[
        PlaybackEpisode(name: '1', url: 'u1'),
      ];
      int? selected;
      final PlayerControlsController c = PlayerControlsController(episodes: eps);
      c.onSelectEpisode = (int i) => selected = i;
      c.selectEpisode(5);
      expect(selected, isNull);
      c.selectEpisode(-1);
      expect(selected, isNull);
    });

    test('selectQuality / selectSpeed / selectBackend 回调 + 关闭面板', () {
      int? q;
      double? sp;
      PlayerBackend? b;
      final PlayerControlsController c = PlayerControlsController(
        qualities: const <String>['标清', '高清'],
        backends: const <PlayerBackend>[PlayerBackend.media3, PlayerBackend.libVLC],
      );
      c.onSelectQuality = (int i) => q = i;
      c.onSelectSpeed = (double s) => sp = s;
      c.onSelectBackend = (PlayerBackend x) => b = x;
      c.selectQuality(1);
      expect(q, 1);
      expect(c.selectedQuality, 1);
      c.selectSpeed(1.5);
      expect(sp, 1.5);
      expect(c.speed, 1.5);
      c.selectBackend(PlayerBackend.libVLC);
      expect(b, PlayerBackend.libVLC);
      expect(c.currentBackend, PlayerBackend.libVLC);
    });

    test('selectQuality 越界忽略', () {
      int? q;
      final PlayerControlsController c = PlayerControlsController(
        qualities: const <String>['标清'],
      );
      c.onSelectQuality = (int i) => q = i;
      c.selectQuality(3);
      expect(q, isNull);
    });

    test('selectBackend 列表外忽略', () {
      PlayerBackend? b;
      final PlayerControlsController c = PlayerControlsController(
        backends: const <PlayerBackend>[PlayerBackend.media3],
      );
      c.onSelectBackend = (PlayerBackend x) => b = x;
      c.selectBackend(PlayerBackend.libmpv); // 不在列表
      expect(b, isNull);
    });

    test('togglePlay / goPrev / goNext 经回调上抛', () {
      int play = 0, prev = 0, next = 0;
      final PlayerControlsController c = PlayerControlsController();
      c.onTogglePlay = () => play++;
      c.onPrevEpisode = () => prev++;
      c.onNextEpisode = () => next++;
      c.togglePlay();
      c.goPrevEpisode();
      c.goNextEpisode();
      expect(play, 1);
      expect(prev, 1);
      expect(next, 1);
    });
  });

  group('面板互斥', () {
    PlayerControlsController controller() => PlayerControlsController();

    test('openEpisodePicker 关闭其它面板', () {
      final PlayerControlsController c = controller();
      c.openQualityPicker();
      expect(c.showQualityPicker, isTrue);
      c.openEpisodePicker();
      expect(c.showEpisodePicker, isTrue);
      expect(c.showQualityPicker, isFalse);
    });

    test('hasAnyPanelOpen 聚合', () {
      final PlayerControlsController c = controller();
      expect(c.hasAnyPanelOpen, isFalse);
      c.openSpeedPicker();
      expect(c.hasAnyPanelOpen, isTrue);
    });

    test('closeAllPanels 关闭全部', () {
      final PlayerControlsController c = controller();
      c.openToolsMenu();
      expect(c.showToolsMenu, isTrue);
      c.closeAllPanels();
      expect(c.hasAnyPanelOpen, isFalse);
    });

    test('逐个打开六种面板', () {
      final PlayerControlsController c = controller();
      c.openEpisodePicker();
      expect(c.showEpisodePicker, isTrue);
      c.openQualityPicker();
      expect(c.showQualityPicker, isTrue);
      c.openSpeedPicker();
      expect(c.showSpeedPicker, isTrue);
      c.openEnginePicker();
      expect(c.showEnginePicker, isTrue);
      c.openDanmakuSettings();
      expect(c.showDanmakuSettings, isTrue);
      c.openToolsMenu();
      expect(c.showToolsMenu, isTrue);
    });
  });

  group('构造默认值', () {
    test('未开播初始态', () {
      final PlayerControlsController c = PlayerControlsController();
      expect(c.title, isNull);
      expect(c.isPlaying, isFalse);
      expect(c.isFullscreen, isFalse);
      expect(c.positionMs, 0);
      expect(c.durationMs, 0);
      expect(c.isLive, isFalse);
      expect(c.speed, 1.0);
      expect(c.qualities, isEmpty);
      expect(c.episodes, isEmpty);
      expect(c.currentBackend, isNull);
      expect(c.showDanmaku, isFalse);
      expect(c.hasDanmaku, isFalse);
    });
  });
}