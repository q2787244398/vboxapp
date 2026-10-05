/// 表现层：全屏播放页（Wave A · R-渲2）。
///
/// 对齐 iOS `VideoPlayerViewV2` / `PlayerControlsView`
/// （[PlayerViewsV2.swift](../../../../vbox/Views/PlayerViewsV2.swift#L537) /
/// [L8313](../../../../vbox/Views/PlayerViewsV2.swift#L8313)）的承载结构：
///  - 黑底 → 画面层（[VideoSurface]）→ 控制层（[PlayerControlsView]）叠加；
///  - 控制层自动隐藏（5s 无操作 / 点按切换；面板打开或暂停时不隐藏）；
///  - 沉浸式全屏；横竖形态由窗口尺寸驱动 [PlayerControlsController.form]；
///  - 方向锁定按钮固定左缘垂直居中（对齐 iOS）；顶栏旋转按钮切换横竖屏；
///  - 选集切换：经 [onResolveEpisode] 重新解析后重开（对齐 iOS 预解析集数语义）。
///
/// 播放生命周期由本页持有：进入即 `open` + `play`；退出仅 `pause`（播放器实例
/// 保持，详情页状态不丢）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/entities/player/player.dart';
import '../../../domain/entities/playback/playback_detail.dart';
import '../../../platform/player/channel_player.dart';
import '../../../platform/player/danmaku/danmaku_settings.dart';
import '../../../platform/player/player_controller.dart';
import '../../../platform/player/playback_route.dart';
import '../../ui_mode/ui_mode.dart';
import '../../widgets/player/player_controls_controller.dart';
import '../../widgets/player/player_controls_view.dart';
import '../../widgets/player/video_surface.dart';

/// 单集 → 播放源解析器（选集重开用；返回 null 表示解析失败）。
typedef EpisodeSourceResolver = Future<PlayerSource?> Function(
  PlaybackEpisode episode,
);

/// 全屏播放页。
class PlayerPage extends StatefulWidget {
  /// 构造。
  const PlayerPage({
    super.key,
    required this.source,
    required this.title,
    this.subtitle,
    this.episodes = const <PlaybackEpisode>[],
    this.initialEpisodeIndex = 0,
    this.qualities = const <String>[],
    this.onResolveEpisode,
    this.route,
    this.controller,
  });

  /// 首个播放源（详情页已解析好的直链 + 鉴权头）。
  final PlayerSource source;

  /// 主标题（剧名）。
  final String title;

  /// 副标题（集名 / 源名）。
  final String? subtitle;

  /// 预解析剧集列表（选集面板数据源，对齐 iOS `preParsedEpisodes`）。
  final List<PlaybackEpisode> episodes;

  /// 首播集索引。
  final int initialEpisodeIndex;

  /// 可选清晰度文案（空表隐藏清晰度按钮）。
  final List<String> qualities;

  /// 选集重开解析器（null 时选集只切 UI 不换源 → 面板禁用）。
  final EpisodeSourceResolver? onResolveEpisode;

  /// 显式播放路由覆盖（F-08：网盘直链无法自证 `pan` 路由，由入口传入）。
  final PlaybackRoute? route;

  /// 播放器控制器（缺省 `PlayerController.instance`；测试注入假实现）。
  final PlayerController? controller;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  /// 控制层自动隐藏延时（对齐 iOS `resetAutoHideTimer` 的 5s 无操作）。
  static const Duration _autoHideDelay = Duration(seconds: 5);

  /// 锁定态锁按钮自动隐藏延时（对齐 iOS `resetLockButtonAutoHide` 的 3s）。
  static const Duration _lockHideDelay = Duration(seconds: 3);

  late final PlayerController _player;
  final PlayerControlsController _controls = PlayerControlsController();

  DanmakuSettings _danmaku = DanmakuSettings.defaults;

  /// 当前输出面纹理句柄（R-渲1）。
  int? _textureId;

  /// 视频纵横比（宽 / 高；null = 未上报 → 铺满）。
  double? _aspectRatio;

  bool _controlsVisible = true;

  /// 锁定态锁按钮是否可见（对齐 iOS `lockButtonVisible`）。
  bool _lockButtonVisible = true;
  bool _landscape = false;
  Timer? _hideTimer;
  Timer? _lockHideTimer;
  Timer? _rotateResetTimer;

  @override
  void initState() {
    super.initState();
    _player = widget.controller ?? PlayerController.instance;
    _bindPlayer();
    _bindControls();
    final int initialIndex = widget.episodes.isEmpty
        ? 0
        : widget.initialEpisodeIndex.clamp(0, widget.episodes.length - 1);
    _controls
      ..title = widget.title
      ..subtitle = widget.subtitle
      ..episodes = widget.episodes
      ..currentEpisodeIndex = initialIndex
      ..qualities = widget.qualities
      ..backends = _player.availableBackends
      ..hasDanmaku = true
      ..showDanmaku = _danmaku.enabled;
    unawaited(_loadDanmaku());
    unawaited(_enter());
  }

  Future<void> _loadDanmaku() async {
    DanmakuSettings s = DanmakuSettings.defaults;
    try {
      s = await DanmakuSettings.load();
    } catch (_) {
      // 未初始化存储（如单测）→ 用会话默认，不阻断播放页。
    }
    if (!mounted) return;
    setState(() {
      _danmaku = s;
      _controls.showDanmaku = s.enabled;
    });
  }

  /// 进入播放页：沉浸式全屏 → 打开并起播。
  ///
  /// 系统 UI 通道在单测环境无宿主（Future 不回调），故**不置于关键路径前**：
  /// 起播优先，沉浸式切换 fire-and-forget。
  Future<void> _enter() async {
    unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    await _openSource(widget.source);
    _scheduleHide();
  }

  // ─────────────── 播放器接线 ───────────────

  void _bindPlayer() {
    _player.onStateChanged = (PlayerState s) {
      if (!mounted) return;
      _controls.updatePlaying(s == PlayerState.playing);
      if (s == PlayerState.ended) unawaited(_onEnded());
    };
    _player.onProgress = (PlaybackProgress p) {
      if (!mounted) return;
      _controls.updateProgress(
        positionMs: p.positionMs,
        durationMs: p.durationMs,
        bufferedMs: p.bufferedMs,
        isLive: p.isLive,
      );
    };
    _player.onVideoSize = (int width, int height) {
      if (!mounted) return;
      setState(() => _aspectRatio = width / height);
    };
    _player.onSurfaceChanged = (int? id) {
      if (!mounted) return;
      setState(() => _textureId = id);
    };
    _player.onError = (String message, {required bool fatal}) {
      if (!mounted) return;
      _toast(message);
    };
  }

  void _bindControls() {
    _controls.onTogglePlay = () => unawaited(_player.togglePlay());
    _controls.onSeek = (int ms) => unawaited(_player.seekTo(ms));
    _controls.onSelectSpeed = (double s) => unawaited(_player.setSpeed(s));
    _controls.onSelectBackend = (PlayerBackend b) => unawaited(_switchBackend(b));
    _controls.onBack = () {
      if (mounted) Navigator.of(context).maybePop();
    };
    _controls.onToggleOrientationLock = () => unawaited(_toggleOrientationLock());
    // 顶栏旋转按钮：切换横竖屏（对齐 iOS `rotate.left` / `rotate.right`）。
    _controls.onToggleFullscreen = () => unawaited(_rotate());
    _controls.onToggleToolsMenu = () {
      _showControls();
      _controls.openToolsMenu();
    };
    _controls.onToggleDanmakuSettings = () {
      _showControls();
      _controls.openDanmakuSettings();
    };
    _controls.onToggleDanmaku = () {
      _controls.setDanmakuEnabled(!_controls.showDanmaku);
      setState(() => _danmaku = _danmaku.copyWith(enabled: _controls.showDanmaku));
    };
    final bool canSwitchEpisode = widget.onResolveEpisode != null;
    _controls.onSelectEpisode = canSwitchEpisode ? _playEpisode : null;
    _controls.onNextEpisode = canSwitchEpisode
        ? () {
            final int next = _controls.currentEpisodeIndex + 1;
            if (next < widget.episodes.length) unawaited(_playEpisode(next));
          }
        : null;
    _controls.onPrevEpisode = canSwitchEpisode
        ? () {
            final int prev = _controls.currentEpisodeIndex - 1;
            if (prev >= 0) unawaited(_playEpisode(prev));
          }
        : null;
  }

  /// 打开播放源并起播；失败抛 [PlayerOpenException] 已在导航层处理，此处仅提示。
  Future<void> _openSource(PlayerSource source) async {
    try {
      await _player.open(source, route: widget.route);
      await _player.play();
      if (!mounted) return;
      _controls.currentBackend = _player.backend;
    } on PlayerOpenException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  /// 切换内核（P-芯2）：以当前源在指定后端重开。
  Future<void> _switchBackend(PlayerBackend backend) async {
    await _player.switchBackend(backend);
    if (!mounted) return;
    _controls.currentBackend = _player.backend;
  }

  /// 选集重开（对齐 iOS 预解析集数：解析 → 重开 → 回填当前集）。
  Future<void> _playEpisode(int index) async {
    final EpisodeSourceResolver? resolver = widget.onResolveEpisode;
    if (resolver == null) return;
    if (index < 0 || index >= widget.episodes.length) return;
    final PlaybackEpisode episode = widget.episodes[index];
    _controls.applyEpisode(
      index,
      subtitle: episode.name.isEmpty ? null : episode.name,
    );
    final PlayerSource? source = await resolver(episode);
    if (!mounted || source == null) return;
    await _openSource(source);
    _scheduleHide();
  }

  /// 播放结束：自动连播下一集（对齐 iOS `autoPlayNext` 默认开）。
  Future<void> _onEnded() async {
    final int next = _controls.currentEpisodeIndex + 1;
    if (widget.onResolveEpisode != null && next < widget.episodes.length) {
      await _playEpisode(next);
    }
  }

  // ─────────────── 控制层显隐 ───────────────

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  /// 点击屏幕：锁定态仅短暂唤出锁按钮（3s）；解锁态切换控制层显隐。
  void _toggleControls() {
    if (_controls.orientationLocked) {
      setState(() => _lockButtonVisible = true);
      _scheduleLockHide();
      return;
    }
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHideDelay, () {
      if (!mounted) return;
      // 面板打开 → 顺延；暂停中 → 不隐藏（对齐 iOS 交互）。
      if (_controls.hasAnyPanelOpen) {
        _scheduleHide();
        return;
      }
      if (!_controls.isPlaying) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _scheduleLockHide() {
    _lockHideTimer?.cancel();
    _lockHideTimer = Timer(_lockHideDelay, () {
      if (!mounted) return;
      setState(() => _lockButtonVisible = false);
    });
  }

  // ─────────────── 方向 / 系统 UI ───────────────

  /// 方向锁定切换（左缘锁按钮）：锁定后隐藏控制层，防误触。
  Future<void> _toggleOrientationLock() async {
    final bool locked = !_controls.orientationLocked;
    _controls.setOrientationLocked(locked);
    if (locked) {
      _hideTimer?.cancel();
      setState(() => _lockButtonVisible = true);
      _scheduleLockHide();
    } else {
      _lockHideTimer?.cancel();
      setState(() => _lockButtonVisible = true);
      _showControls();
    }
    unawaited(SystemChrome.setPreferredOrientations(
      locked
          ? const <DeviceOrientation>[
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : DeviceOrientation.values,
    ));
  }

  /// 顶栏旋转按钮：强制切到对侧方向，0.5s 后恢复自由旋转（对齐 iOS 行为）。
  Future<void> _rotate() async {
    final bool toLandscape = !_landscape;
    _rotateResetTimer?.cancel();
    await SystemChrome.setPreferredOrientations(toLandscape
        ? const <DeviceOrientation>[
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : const <DeviceOrientation>[DeviceOrientation.portraitUp]);
    _rotateResetTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        unawaited(
            SystemChrome.setPreferredOrientations(DeviceOrientation.values));
      }
    });
  }

  /// 退出播放页：恢复正常系统 UI + 全方向（fire-and-forget，不阻塞返回）。
  void _restoreSystemUi() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(
        SystemChrome.setPreferredOrientations(DeviceOrientation.values));
  }

  void _onDanmakuChanged(DanmakuSettings settings) {
    final DanmakuSettings normalized = settings.normalized();
    setState(() {
      _danmaku = normalized;
      _controls.setDanmakuEnabled(normalized.enabled);
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _lockHideTimer?.cancel();
    _rotateResetTimer?.cancel();
    _player.onStateChanged = null;
    _player.onProgress = null;
    _player.onVideoSize = null;
    _player.onSurfaceChanged = null;
    _player.onError = null;
    unawaited(_player.pause());
    _restoreSystemUi();
    _controls.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final bool landscape = size.width > size.height;
    if (_landscape != landscape) {
      _landscape = landscape;
      // 直接写字段（不 notify）：本次 build 即取新形态，避免 build 期通知。
      _controls.form = landscape ? UiForm.landscape : UiForm.portrait;
    }
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) _restoreSystemUi();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          onDoubleTap: () => unawaited(_player.togglePlay()),
          child: PlayerControlsView(
            controller: _controls,
            lockButtonVisible: _lockButtonVisible,
            controlsVisible: _controlsVisible,
            danmakuSettings: _danmaku,
            onDanmakuSettingsChanged: _onDanmakuChanged,
            videoBuilder: (BuildContext context) => VideoSurface(
              textureId: _textureId,
              aspectRatio: _aspectRatio,
            ),
          ),
        ),
      ),
    );
  }
}