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
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../domain/entities/player/player.dart';
import '../../../domain/entities/playback/playback_detail.dart';
import '../../../platform/player/cast/cast.dart';
import '../../../platform/player/cast/dlna_cast_service.dart';
import '../../../platform/player/channel_player.dart';
import '../../../platform/player/danmaku/danmaku_controller.dart';
import '../../../platform/player/danmaku/danmaku_item.dart';
import '../../../platform/player/danmaku/danmaku_lane_engine.dart';
import '../../../platform/player/danmaku/danmaku_service.dart';
import '../../../platform/player/danmaku/danmaku_settings.dart';
import '../../../platform/player/floating/floating.dart';
import '../../../platform/player/media_url_checker.dart';
import '../../../platform/player/pip/pip.dart';
import '../../../platform/player/player_controller.dart';
import '../../../platform/player/playback_route.dart';
import '../../../platform/player/playback_settings.dart';
import '../../../platform/player/playthrough.dart';
import '../../../platform/player/remux_proxy.dart';
import '../../../platform/player/subtitle_parser.dart';
import '../../theme/tokens/colors.dart';
import '../../ui_mode/ui_mode.dart';
import '../../widgets/player/cast/cast_controller.dart';
import '../../widgets/player/cast/cast_device_sheet.dart';
import '../../widgets/player/danmaku/danmaku_overlay.dart';
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
    this.subtitleUrl,
    this.episodes = const <PlaybackEpisode>[],
    this.initialEpisodeIndex = 0,
    this.qualities = const <String>[],
    this.onResolveEpisode,
    this.route,
    this.controller,
    this.danmakuService,
    this.castService,
  });

  /// 首个播放源（详情页已解析好的直链 + 鉴权头）。
  final PlayerSource source;

  /// 主标题（剧名）。
  final String title;

  /// 副标题（集名 / 源名）。
  final String? subtitle;

  /// 外挂字幕地址（`srt` / `vtt` / `ass`；null 表示无字幕，可经「更多 → 加载字幕」补挂）。
  ///
  /// 对齐 iOS `PlayerState.loadSubtitle(url:)`：进入播放页时自动加载并解析。
  final String? subtitleUrl;

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

  /// 弹幕数据源（缺省按弹幕设置自建；测试注入假实现，不触网）。
  final DanmakuService? danmakuService;

  /// 投屏服务（缺省 DLNA；测试注入假实现）。
  final CastService? castService;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  /// 控制层自动隐藏延时（对齐 iOS `resetAutoHideTimer` 的 5s 无操作）。
  static const Duration _autoHideDelay = Duration(seconds: 5);

  /// 锁定态锁按钮自动隐藏延时（对齐 iOS `resetLockButtonAutoHide` 的 3s）。
  static const Duration _lockHideDelay = Duration(seconds: 3);

  late final PlayerController _player;
  final PlayerControlsController _controls = PlayerControlsController();

  DanmakuSettings _danmaku = DanmakuSettings.defaults;

  /// 弹幕数据源（设置加载后自建或由调用方注入）。
  DanmakuService? _danmakuService;

  /// 弹幕播放控制器（按视口尺寸重建）。
  DanmakuPlaybackController? _danmakuCtrl;

  /// 当前集弹幕全量（用于重建控制器 / 本地乐观注入）。
  List<DanmakuItem> _danmakuItems = const <DanmakuItem>[];

  /// 当前应渲染的弹幕状态（定时器逐帧产出）。
  List<DanmakuRenderState> _danmakuStates = const <DanmakuRenderState>[];

  /// 命中的弹幕 episodeId（发送弹幕复用；未命中为 null）。
  int? _danmakuEpisodeId;

  /// 弹幕渲染定时器（播放中每 60ms 推进一次）。
  Timer? _danmakuTimer;

  /// 最近一次进度事件的位置与接收墙钟（定时器内插值出连续播放时刻）。
  int _danmakuPosMs = 0;
  int _danmakuSyncAtMs = 0;

  /// 弹幕引擎视口尺寸（随窗口变化重建控制器）。
  Size _danmakuViewport = Size.zero;

  /// 投屏服务与控制器（C-09）。
  late final CastService _castService;
  late final CastController _castController;

  /// 播放行为设置（C-05：画中画 / 后台 / 连播 / 长按倍速；未读到前用契约默认）。
  PlaybackSettings _playback = const PlaybackSettings(
    pipEnabled: true,
    backgroundPlay: false,
    autoPlayNext: true,
    longPressSpeed: 2.0,
  );

  /// 自动连播控制（C-05；`ended` 时按开关推进下一集）。
  late final AutoPlayNextController _autoPlayNext;

  /// 长按倍速控制（C-05）。
  late final LongPressSpeedController _longPressSpeed;

  /// 播放前直链探测（C-12；首开失败时区分「地址不可达」与「后端不支持」）。
  MediaUrlChecker? _urlChecker;

  /// 后台播放控制（C-05；退后台启动前台媒体服务）。
  BackgroundPlayController? _backgroundPlay;

  /// 画中画控制（C-05；按渲染内核 / 平台能力多策略分派）。
  PipController? _pip;

  /// 外挂字幕轨道（C-08；null 表示未加载）。
  SubtitleTrack? _subtitleTrack;

  /// 当前应显示的字幕文本（随进度更新）。
  String? _subtitleCueText;

  /// 长按倍速是否激活（驱动提示浮层）。
  bool _longPressSpeedActive = false;

  /// 长按前的倍速（松开恢复用）。
  double _preLongPressSpeed = 1.0;

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
    _castService = widget.castService ?? DlnaCastService();
    _castController = CastController(service: _castService);
    _controls.castAvailable = _castController.isAvailable;
    _bindPlayer();
    _bindControls();
    _autoPlayNext = AutoPlayNextController(
      enabled: _playback.autoPlayNext,
      onAdvance: () => unawaited(_advanceNext()),
    );
    _longPressSpeed = LongPressSpeedController(
      longPressSpeed: _playback.longPressSpeed,
      currentSpeed: () => _controls.speed,
      setSpeed: (double s) => _player.setSpeed(s),
    );
    WidgetsBinding.instance.addObserver(this);
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
    unawaited(_initDanmaku());
    unawaited(_enter());
    unawaited(_loadCapabilities());
  }

  // ─────────────── 弹幕接线（C-03） ───────────────

  /// 初始化弹幕：读设置 → 建数据源 → 拉取当前集 → 启动渲染定时器。
  ///
  /// 存储未初始化（如单测）→ 用会话默认，不阻断播放页。
  Future<void> _initDanmaku() async {
    DanmakuSettings s = DanmakuSettings.defaults;
    try {
      s = await DanmakuSettings.load();
    } catch (_) {
      // 忽略：回退会话默认。
    }
    if (!mounted) return;
    setState(() {
      _danmaku = s;
      _controls.showDanmaku = s.enabled;
    });
    _danmakuService = widget.danmakuService ??
        DanmakuService(
          baseUrl: s.customSourceEnabled ? s.customSourceUrl : null,
        );
    _danmakuSyncAtMs = DateTime.now().millisecondsSinceEpoch;
    _danmakuTimer = Timer.periodic(
      const Duration(milliseconds: 60),
      (_) => _tickDanmaku(),
    );
    if (_danmakuItems.isEmpty) _syncDanmakuController();
    await _loadDanmakuItems();
  }

  /// 拉取当前集弹幕并重建控制器（首播 / 切集时调用，失败降级为空）。
  Future<void> _loadDanmakuItems() async {
    final DanmakuService? svc = _danmakuService;
    if (svc == null) return;
    final String query = _danmakuQuery();
    if (query.isEmpty) return;
    final DanmakuFetchResult r = await svc.matchAndFetch(query);
    if (!mounted) return;
    setState(() {
      _danmakuItems = r.items;
      _danmakuEpisodeId = r.episodeId;
      _danmakuStates = const <DanmakuRenderState>[];
    });
    _syncDanmakuController();
  }

  /// 当前集的弹幕查询串（对齐 iOS `bestDanmakuQuery`：剧名 + 集名）。
  String _danmakuQuery() {
    final int idx = _controls.currentEpisodeIndex;
    final List<PlaybackEpisode> eps = widget.episodes;
    if (idx >= 0 && idx < eps.length) {
      final String name = eps[idx].name.trim();
      if (name.isNotEmpty) return '${widget.title} $name';
    }
    return widget.title;
  }

  /// 以当前视口尺寸重建弹幕控制器（引擎坐标与渲染像素一致）。
  void _syncDanmakuController() {
    final Size size = _danmakuViewport == Size.zero
        ? MediaQuery.sizeOf(context)
        : _danmakuViewport;
    _danmakuViewport = size;
    _danmakuCtrl = DanmakuPlaybackController(
      items: _danmakuItems,
      engine: DanmakuLaneEngine(
        viewportWidth: size.width,
        viewportHeight: size.height,
      ),
    );
    _danmakuStates = const <DanmakuRenderState>[];
  }

  /// 播放中逐帧推进弹幕（进度事件间隔内以墙钟插值，保证平滑滚动）。
  void _tickDanmaku() {
    final DanmakuPlaybackController? ctrl = _danmakuCtrl;
    if (ctrl == null || !_controls.showDanmaku || !_controls.isPlaying) return;
    final int nowMs = _danmakuPosMs +
        (DateTime.now().millisecondsSinceEpoch - _danmakuSyncAtMs);
    final List<DanmakuRenderState> states = ctrl.tick(nowMs);
    if (!mounted) return;
    setState(() => _danmakuStates = states);
  }

  /// 打开弹幕输入框并发送（对齐 iOS 横屏弹幕输入）。
  Future<void> _promptSendDanmaku() async {
    final TextEditingController input = TextEditingController();
    final String? text = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('发送弹幕'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(hintText: '输入弹幕内容'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(input.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    input.dispose();
    if (text == null || text.isEmpty) return;
    await _sendDanmaku(text);
  }

  /// 发送弹幕：先本地立即显示（乐观更新），再异步提交服务器。
  Future<void> _sendDanmaku(String content) async {
    final int nowMs = _danmakuPosMs +
        (DateTime.now().millisecondsSinceEpoch - _danmakuSyncAtMs);
    final DanmakuItem item = DanmakuItem(
      content: content,
      timeMs: nowMs,
      id: 'local-$nowMs',
    );
    if (mounted) {
      setState(() {
        _danmakuItems = <DanmakuItem>[..._danmakuItems, item];
        final DanmakuPlaybackController? ctrl = _danmakuCtrl;
        if (ctrl != null) {
          ctrl.inject(item);
          // 立即渲染（暂停态也能看到自己的弹幕；播放中下帧由定时器接管）。
          _danmakuStates = ctrl.tick(nowMs);
        }
      });
    }
    final DanmakuService? svc = _danmakuService;
    final int? episodeId = _danmakuEpisodeId;
    if (svc == null || episodeId == null) return;
    final bool ok = await svc.send(
      episodeId: episodeId,
      content: content,
      timeSec: nowMs / 1000.0,
    );
    if (!ok && mounted) _toast('弹幕发送失败');
  }

  // ─────────────── 投屏接线（C-09） ───────────────

  /// 打开投屏设备选择弹层；投屏成功后暂停本地播放（避免双端出声）。
  Future<void> _openCastSheet() async {
    _showControls();
    final bool? casted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: VboxColors.playerPanelBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext ctx) => CastDeviceSheet(
        controller: _castController,
        media: _currentCastMedia(),
      ),
    );
    if (casted == true) await _player.pause();
  }

  /// 当前待投送媒体（对齐 iOS 投屏的媒体投影）。
  CastMedia _currentCastMedia() => CastMedia(
        url: widget.source.url,
        title: widget.title,
        headers: widget.source.headers,
        isLive: _controls.isLive,
        positionMs: _controls.positionMs,
      );

  // ─────────────── 播放能力接线（C-05 / C-08） ───────────────

  /// 读取播放行为设置并接线后台播放 / 画中画 / 字幕。
  ///
  /// 未初始化存储（如单测）→ 保持契约默认，不阻断播放页。
  Future<void> _loadCapabilities() async {
    PlaybackSettings s = _playback;
    try {
      s = await PlaybackSettings.load();
    } catch (_) {
      // 忽略：回退会话默认。
    }
    if (!mounted) return;
    setState(() {
      _playback = s;
      _autoPlayNext.enabled = s.autoPlayNext;
      _controls.pipAvailable = s.pipEnabled;
    });
    _backgroundPlay = BackgroundPlayController(
      enabled: s.backgroundPlay,
      bridge: MethodChannelBackgroundPlayBridge(),
    );
    await _initPip(s);
    final String? subtitleUrl = widget.subtitleUrl;
    if (subtitleUrl != null && subtitleUrl.trim().isNotEmpty) {
      await _loadSubtitle(subtitleUrl);
    }
  }

  /// 解析画中画策略并创建控制器（原生不可用 → 保持 null，入口隐藏）。
  Future<void> _initPip(PlaybackSettings s) async {
    PipController pip;
    try {
      pip = await PipController.resolveAndCreate(
        enabled: s.pipEnabled,
        platform: Platform.operatingSystem,
        backend: _player.backend,
        systemBridge: MethodChannelPipBridge(),
        floating: MethodChannelFloatingWindow(),
        backgroundPlayEnabled: s.backgroundPlay,
      );
    } catch (_) {
      // 原生桥缺失（桌面 / 单测）→ 不接画中画，不阻断播放。
      return;
    }
    if (!mounted) {
      await pip.dispose();
      return;
    }
    setState(() {
      _pip = pip;
      _controls.pipAvailable = pip.strategy.showsVisualPip;
    });
  }

  /// 生命周期联动：退后台驱动后台播放承载 + 画中画，回前台收回。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final PlaybackLifecycle lifecycle =
        PlaybackLifecycle.fromAppStateName(state.name);
    final bool playing = _controls.isPlaying;
    final BackgroundPlayController? bg = _backgroundPlay;
    if (bg != null) {
      unawaited(bg.handleLifecycle(lifecycle, isPlaying: playing));
    }
    final PipController? pip = _pip;
    if (pip != null) {
      unawaited(pip
          .handleLifecycle(lifecycle, isPlaying: playing)
          .then<void>((_) {
        if (mounted) _controls.setInPip(pip.isInPip);
      }, onError: (Object _) {}));
    }
  }

  /// 「更多 → 画中画」：进入 / 退出画中画。
  Future<void> _togglePip() async {
    final PipController? pip = _pip;
    if (pip == null) return;
    try {
      if (pip.isInPip) {
        await pip.exit();
      } else {
        await pip.enter(title: widget.title, isLive: _controls.isLive);
      }
    } catch (_) {
      // 原生桥异常 → 保持当前状态，不误报。
    }
    if (!mounted) return;
    setState(() => _controls.setInPip(pip.isInPip));
  }

  /// 「更多 → 加载字幕」：输入字幕地址后加载解析。
  Future<void> _promptSubtitleUrl() async {
    final TextEditingController input =
        TextEditingController(text: widget.subtitleUrl ?? '');
    final String? url = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('加载字幕'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: '字幕文件地址（.srt / .vtt / .ass）',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(input.text.trim()),
            child: const Text('加载'),
          ),
        ],
      ),
    );
    input.dispose();
    if (url == null || url.isEmpty) return;
    await _loadSubtitle(url);
  }

  /// 下载并解析外挂字幕（C-08），成功后在画面上叠加显示。
  Future<void> _loadSubtitle(String url) async {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      _toast('字幕地址无效');
      return;
    }
    try {
      final http.Response resp = await http.get(uri);
      if (resp.statusCode != 200) {
        if (mounted) _toast('字幕加载失败（HTTP ${resp.statusCode}）');
        return;
      }
      final List<SubtitleCue> cues = SubtitleParser.parseBytes(resp.bodyBytes);
      if (cues.isEmpty) {
        if (mounted) _toast('字幕解析失败或为空');
        return;
      }
      if (!mounted) return;
      setState(() {
        _subtitleTrack = SubtitleTrack(cues);
        _subtitleCueText = null;
      });
      _toast('字幕已加载（${cues.length} 条）');
    } catch (_) {
      if (mounted) _toast('字幕加载失败');
    }
  }

  /// 随进度更新当前字幕文本（仅在变化时刷新）。
  void _updateSubtitleCue(int positionMs) {
    final SubtitleTrack? track = _subtitleTrack;
    if (track == null) return;
    final String? text = track.cueAt(positionMs)?.text;
    if (text == _subtitleCueText) return;
    setState(() => _subtitleCueText = text);
  }

  /// 长按屏幕：切到长按倍速并显示提示浮层。
  Future<void> _beginLongPressSpeed() async {
    if (!_longPressSpeed.enabled) return;
    _preLongPressSpeed = _controls.speed;
    try {
      await _longPressSpeed.begin();
    } catch (_) {
      // 后端设速失败 → 不改显示状态。
    }
    if (!mounted) return;
    setState(() {
      _longPressSpeedActive = true;
      _controls.applySpeed(_longPressSpeed.longPressSpeed);
    });
  }

  /// 松开：恢复长按前的倍速并隐藏提示浮层。
  Future<void> _endLongPressSpeed() async {
    if (!_longPressSpeed.isActive) return;
    try {
      await _longPressSpeed.end();
    } catch (_) {
      // 后端设速失败 → 仍回填显示，避免卡在长按态。
    }
    if (!mounted) return;
    setState(() {
      _longPressSpeedActive = false;
      _controls.applySpeed(_preLongPressSpeed);
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
      // C-05 自动连播：由控制器按开关决定是否推进下一集。
      _autoPlayNext.handleState(s);
    };
    _player.onProgress = (PlaybackProgress p) {
      if (!mounted) return;
      _controls.updateProgress(
        positionMs: p.positionMs,
        durationMs: p.durationMs,
        bufferedMs: p.bufferedMs,
        isLive: p.isLive,
      );
      _updateSubtitleCue(p.positionMs);
      // 弹幕时基同步（定时器在两次进度事件间按墙钟插值）。
      _danmakuPosMs = p.positionMs;
      _danmakuSyncAtMs = DateTime.now().millisecondsSinceEpoch;
      final PipController? pip = _pip;
      if (pip != null && pip.isInPip) {
        unawaited(pip.updateProgress(p.positionMs, p.durationMs));
      }
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
    // 拖拽跳转：弹幕光标重排（对齐 iOS 拖拽后弹幕重排）。
    _controls.onSeek = (int ms) {
      _danmakuCtrl?.seekTo(ms);
      _danmakuPosMs = ms;
      _danmakuSyncAtMs = DateTime.now().millisecondsSinceEpoch;
      if (mounted) setState(() => _danmakuStates = const <DanmakuRenderState>[]);
      unawaited(_player.seekTo(ms));
    };
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
    _controls.onTogglePip = () => unawaited(_togglePip());
    _controls.onLoadSubtitle = () => unawaited(_promptSubtitleUrl());
    _controls.onSendDanmaku = () => unawaited(_promptSendDanmaku());
    _controls.onCast = () => unawaited(_openCastSheet());
  }

  /// 打开播放源并起播；失败抛 [PlayerOpenException] 已在导航层处理，此处仅提示。
  ///
  /// 首开后端不支持时按两条既有能力补救（C-07 / C-12）：
  ///  1. 复杂封装（MKV / FLV / TS…）经转封装代理换 fMP4 容器重试一次；
  ///  2. 仍失败则探测直链可达性，给出精确诊断（地址不可达 vs 地址不可用）。
  Future<void> _openSource(PlayerSource source) async {
    try {
      await _player.open(source, route: widget.route);
      await _player.play();
      if (!mounted) return;
      _controls.currentBackend = _player.backend;
    } on PlayerOpenException catch (e) {
      final PlayerSource? remuxed = await _remuxFallback(source);
      if (remuxed != null) {
        try {
          await _player.open(remuxed, route: widget.route);
          await _player.play();
          if (!mounted) return;
          _controls.currentBackend = _player.backend;
          return;
        } on PlayerOpenException {
          // 转封装后仍失败 → 走下方统一诊断提示。
        }
      }
      final String message = await _diagnose(e, source);
      if (mounted) _toast(message);
    }
  }

  /// 复杂封装 → 转封装候选（C-07）。
  ///
  /// 仅当上游需换容器（[RemuxPlan.needsRemux]）且非直播时，经共享 [RemuxProxy]
  /// （端口 18081）注册流并返回 `fmt=fmp4` 本地地址（对齐 iOS
  /// `MPVAVPlayerPiPProxy.tryRemuxPath` 的转封装重试）；否则返回 null。
  Future<PlayerSource?> _remuxFallback(PlayerSource source) async {
    if (source.isLive ||
        !RemuxPlan.decide(source.url, headers: source.headers).needsRemux) {
      return null;
    }
    try {
      final RemuxProxy proxy = RemuxProxyRegistry.instance;
      if (!proxy.isRunning) await proxy.start();
      final String id =
          proxy.registerStream(url: source.url, headers: source.headers);
      return PlayerSource(
        url: '${proxy.baseUrl}/remux?id=$id&fmt=fmp4',
        title: source.title,
      );
    } catch (_) {
      // 转封装代理不可用 → 不作补救，交原错误提示。
      return null;
    }
  }

  /// 首开失败诊断（C-12）：探测直链可达性，返回更精确的失败文案。
  Future<String> _diagnose(PlayerOpenException e, PlayerSource source) async {
    final MediaUrlChecker checker = _urlChecker ??= MediaUrlChecker();
    try {
      final MediaUrlCheckResult r =
          await checker.check(source.url, headers: source.headers);
      if (!r.reachable) {
        final int? code = r.statusCode;
        return code == null ? '播放地址不可达（网络错误）' : '播放地址不可用（HTTP $code）';
      }
    } catch (_) {
      // 探测失败 → 回落原始错误描述。
    }
    return e.message;
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
    // 切集 → 重新拉取该集弹幕并重置进度时基。
    _danmakuPosMs = 0;
    _danmakuSyncAtMs = DateTime.now().millisecondsSinceEpoch;
    unawaited(_loadDanmakuItems());
    _scheduleHide();
  }

  /// 自动连播推进目标（[AutoPlayNextController.onAdvance] 接线；对齐 iOS `autoPlayNext`）。
  ///
  /// 是否推进由控制器按契约键 `player_auto_play_next` 决定；本方法只负责
  /// 「有解析器且有下一集」时切集，无下一集则 no-op。
  Future<void> _advanceNext() async {
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
    _danmakuTimer?.cancel();
    _castController.dispose();
    final CastService cast = _castService;
    if (cast is DlnaCastService) cast.close();
    if (widget.danmakuService == null) _danmakuService?.close();
    _player.onStateChanged = null;
    _player.onProgress = null;
    _player.onVideoSize = null;
    _player.onSurfaceChanged = null;
    _player.onError = null;
    WidgetsBinding.instance.removeObserver(this);
    final PipController? pip = _pip;
    if (pip != null) unawaited(pip.dispose());
    final BackgroundPlayController? bg = _backgroundPlay;
    if (bg != null) unawaited(bg.dispose());
    _urlChecker?.dispose();
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
    // 窗口尺寸变化 → 重建弹幕引擎（坐标与渲染像素一致）。
    if (_danmakuViewport != size) {
      _danmakuViewport = size;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_syncDanmakuController);
      });
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
          // C-05 长按倍速：按住加速，松开恢复（未启用则不占用长按手势）。
          onLongPressStart: _longPressSpeed.enabled
              ? (LongPressStartDetails _) => unawaited(_beginLongPressSpeed())
              : null,
          onLongPressEnd: _longPressSpeed.enabled
              ? (LongPressEndDetails _) => unawaited(_endLongPressSpeed())
              : null,
          onLongPressCancel: _longPressSpeed.enabled
              ? () => unawaited(_endLongPressSpeed())
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              PlayerControlsView(
                controller: _controls,
                lockButtonVisible: _lockButtonVisible,
                controlsVisible: _controlsVisible,
                danmakuSettings: _danmaku,
                onDanmakuSettingsChanged: _onDanmakuChanged,
                videoBuilder: (BuildContext context) => VideoSurface(
                  textureId: _textureId,
                  aspectRatio: _aspectRatio,
                ),
                // 弹幕层（叠于画面之上、控制层之下；关开关或无弹幕则不渲染）。
                danmakuBuilder: (BuildContext context) {
                  if (!_controls.showDanmaku || _danmakuStates.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return DanmakuOverlay(
                    states: _danmakuStates,
                    opacity: _danmaku.opacity,
                    area: _danmaku.area,
                    fontSize: _danmaku.fontSize,
                  );
                },
              ),
              // C-08 字幕浮层（随时间更新；不拦截手势）。
              if (_subtitleCueText != null && _subtitleCueText!.isNotEmpty)
                _SubtitleOverlay(text: _subtitleCueText!),
              // C-05 长按倍速提示浮层。
              if (_longPressSpeedActive)
                _LongPressSpeedOverlay(text: _controls.speedDisplayText),
            ],
          ),
        ),
      ),
    );
  }
}

/// 字幕浮层（画面下方居中；对齐 iOS `currentSubtitleText` 叠加）。
class _SubtitleOverlay extends StatelessWidget {
  const _SubtitleOverlay({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24,
      right: 24,
      bottom: 84,
      child: IgnorePointer(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.3,
            shadows: <Shadow>[
              Shadow(blurRadius: 4, color: Colors.black87),
            ],
          ),
        ),
      ),
    );
  }
}

/// 长按倍速提示浮层（画面正中；对齐 iOS `showLongPressSpeedHint`）。
class _LongPressSpeedOverlay extends StatelessWidget {
  const _LongPressSpeedOverlay({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}