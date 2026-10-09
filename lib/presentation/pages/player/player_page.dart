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

import '../../../data/datasources/local/prefs_manager.dart';
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
import '../../../platform/player/gesture/gesture_control.dart';
import '../../../platform/player/gesture/screen_controls.dart';
import '../../../platform/player/media_url_checker.dart';
import '../../../platform/player/pan_fallback_chain.dart';
import '../../../platform/player/pip/pip.dart';
import '../../../platform/player/player_controller.dart';
import '../../../platform/player/playback_progress.dart';
import '../../../platform/player/playback_route.dart';
import '../../../platform/player/playback_settings.dart';
import '../../../platform/player/playthrough.dart';
import '../../../platform/player/remux_proxy.dart';
import '../../../platform/player/skip_settings.dart';
import '../../../platform/player/subtitle_parser.dart';
import '../../../platform/player/subtitle_style.dart';
import '../../../platform/player/wake_lock.dart';
import '../../theme/tokens/colors.dart';
import '../../ui_mode/ui_mode.dart';
import '../../widgets/player/cast/cast_controller.dart';
import '../../widgets/player/cast/cast_device_sheet.dart';
import '../../widgets/player/danmaku/danmaku_overlay.dart';
import '../../widgets/player/gesture_hud.dart';
import '../../widgets/player/player_controls_controller.dart';
import '../../widgets/player/player_controls_view.dart';
import '../../widgets/player/player_error_view.dart';
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
    this.vodId = '',
    this.episodes = const <PlaybackEpisode>[],
    this.initialEpisodeIndex = 0,
    this.qualities = const <String>[],
    this.onResolveEpisode,
    this.onProgress,
    this.route,
    this.controller,
    this.danmakuService,
    this.castService,
    this.wakeLock,
  });

  /// 首个播放源（详情页已解析好的直链 + 鉴权头）。
  final PlayerSource source;

  /// 主标题（剧名）。
  final String title;

  /// 副标题（集名 / 源名）。
  final String? subtitle;

  /// 视频 id（片头片尾设置按视频独立存储的键；空串表示不启用该能力）。
  final String vodId;

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

  /// 播放进度回调（详情页用于写入观看记录，对齐 iOS 进度落库）。
  final void Function(PlaybackProgress progress)? onProgress;

  /// 显式播放路由覆盖（F-08：网盘直链无法自证 `pan` 路由，由入口传入）。
  final PlaybackRoute? route;

  /// 播放器控制器（缺省 `PlayerController.instance`；测试注入假实现）。
  final PlayerController? controller;

  /// 弹幕数据源（缺省按弹幕设置自建；测试注入假实现，不触网）。
  final DanmakuService? danmakuService;

  /// 投屏服务（缺省 DLNA；测试注入假实现）。
  final CastService? castService;

  /// 屏幕常亮控制器（UI-D2，测试可注入；null 用 wakelock_plus 默认实现）。
  final WakeLockController? wakeLock;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  /// 控制层自动隐藏延时（对齐 iOS `resetAutoHideTimer` 的 5s 无操作）。
  static const Duration _autoHideDelay = Duration(seconds: 5);

  /// 锁定态锁按钮自动隐藏延时（对齐 iOS `resetLockButtonAutoHide` 的 3s）。
  static const Duration _lockHideDelay = Duration(seconds: 3);

  /// 下一集预取触发的剩余时长阈值（UI-F17；对齐 iOS 近结尾预取）。
  static const int _preloadRemainMs = 30000;

  late final PlayerController _player;

  /// 屏幕常亮控制器（UI-D2，按播放状态驱动，对齐 iOS `updateIdleTimer`）。
  late final WakeLockController _wakeLock;
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

  /// 片头片尾跳过设置（UI-F2；按 [PlayerPage.vodId] 独立加载）。
  SkipSettings _skipSettings = const SkipSettings();

  /// 本集片头 / 片尾是否已触发（一集内只跳一次，对齐 iOS `skipIntroTriggered`）。
  bool _skipIntroTriggered = false;
  bool _skipOutroTriggered = false;

  /// 待应用的续播位置（毫秒；null = 无记录或已应用；UI-F16）。
  double? _resumePositionMs;

  /// 续播是否已应用（首帧就绪后仅 seek 一次，切集不重复；UI-F16）。
  bool _resumeApplied = false;

  /// 上次进度落库墙钟（节流 5s；UI-F16）。
  int _lastProgressSaveMs = 0;

  /// 已预取的剧集索引与播放源（UI-F17；切集命中则跳过二次解析）。
  int? _preloadedEpisodeIndex;
  PlayerSource? _preloadedSource;

  /// 正在预取的剧集索引（防同一集重复触发；UI-F17）。
  int? _preloadingIndex;

  /// 当前应显示的字幕文本（随进度更新）。
  String? _subtitleCueText;

  /// 长按倍速是否激活（驱动提示浮层）。
  bool _longPressSpeedActive = false;

  /// 长按前的倍速（松开恢复用）。
  double _preLongPressSpeed = 1.0;

  /// 致命错误文案（非 null 时覆盖显示 [PlayerErrorView]；对齐 iOS `ErrorView`）。
  String? _errorMessage;

  /// 播放器运行日志（错误态调试查看用；对齐 iOS `ErrorViewWithLogs`）。
  final List<String> _playerLogs = <String>[];

  /// 视频区手势控制器（UI-F1：亮度 / 音量 / 快进快退）。
  late final PlayerGestureController _gestures;

  /// 手势提示浮层数据（非 null 时显示 `PlayerGestureHud`）。
  GestureAdjustment? _gestureHud;

  /// 本次手势累计位移（手势状态机按「相对起点的总位移」判定）。
  Offset _gestureTranslation = Offset.zero;

  /// 当前输出面纹理句柄（R-渲1）。
  int? _textureId;

  /// 视频纵横比（宽 / 高；null = 未上报 → 铺满）。
  double? _aspectRatio;

  /// 画面拉伸模式（UI-E2，对齐 iOS `PlayerState.videoGravity`；缺省填充）。
  VideoGravityMode _videoGravity = VideoGravityMode.aspectFill;

  bool _controlsVisible = true;

  /// 锁定态锁按钮是否可见（对齐 iOS `lockButtonVisible`）。
  bool _lockButtonVisible = true;
  bool _landscape = false;
  Timer? _hideTimer;
  Timer? _lockHideTimer;
  Timer? _rotateResetTimer;

  /// 跳转加载层的安全超时（UI-F18；对齐 iOS `seekTimeoutTask` 的 3s 兜底）。
  Timer? _seekLoadingTimer;

  /// 是否处于「跳转加载」中（等待首个进度回执或安全超时收起）。
  bool _seekLoadingPending = false;

  /// 是否因退后台被自动暂停（回前台据此恢复；UI-F22）。
  bool _pausedForBackground = false;

  /// 回前台恢复播放的宽限任务（对齐 iOS 800ms 宽限；UI-F22）。
  Timer? _foregroundRestoreTimer;

  /// 网盘播放兜底链（UI-F21；null 表示当前源无兜底线路）。
  PanFallbackChain? _panFallback;

  /// 首帧超时任务（对齐 iOS `quarkFallbackTimeoutTask`；8s 未出画即切兜底）。
  Timer? _panFallbackTimeout;

  /// 首帧是否已就绪（对齐 iOS `playerItem.status == .readyToPlay`）。
  bool _firstFrameReady = false;

  /// 是否处于 `open` 调用中（用于区分「打开期后端降级」与「运行期播放错误」）。
  bool _openingInFlight = false;

  @override
  void initState() {
    super.initState();
    _player = widget.controller ?? PlayerController.instance;
    // UI-D2：屏幕常亮（对齐 iOS isIdleTimerDisabled；播放中开启，暂停/退出恢复）。
    _wakeLock = widget.wakeLock ?? const WakelockPlusController();
    _castService = widget.castService ?? DlnaCastService();
    _castController = CastController(service: _castService);
    _controls.castAvailable = _castController.isAvailable;
    // UI-F1 视频区手势（亮度 / 音量 / 快进快退）；初值异步读取，失败保持 0.5。
    _gestures = PlayerGestureController(screen: _createScreenControlsBridge());
    unawaited(_gestures.load());
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
      ..qualities = widget.qualities.isEmpty
          ? PlayerControlsController.kDefaultQualities
          : widget.qualities
      // R-04：按播放地址探测初始清晰度档（对齐 iOS `detectVideoQuality`）。
      ..selectedQuality =
          PlayerControlsController.detectQualityIndex(widget.source.url) ?? 0
      ..backends = _player.availableBackends
      ..hasDanmaku = true
      ..showDanmaku = _danmaku.enabled
      // UI-F6 工具菜单开关（先用契约默认，稍后由 _loadCapabilities 覆盖）
      ..autoPlayNext = _playback.autoPlayNext
      ..backgroundPlay = _playback.backgroundPlay
      ..pipEnabled = _playback.pipEnabled
      ..longPressSpeed = _playback.longPressSpeed;
    // UI-F18：进入即进入加载态（对齐 iOS `isLoading` 默认 true）。
    _controls.showLoading();
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

  // ─────────────── 弹幕搜索（UI-F3）───────────────

  /// 关键字 → 候选番剧（搜索面板数据源）。
  Future<List<DanmakuAnimeMatch>> _searchDanmakuAnime(String keyword) async {
    final DanmakuService? svc = _danmakuService;
    if (svc == null) return const <DanmakuAnimeMatch>[];
    return svc.searchAnimes(keyword);
  }

  /// 番剧 id → 分集列表（搜索面板数据源）。
  Future<List<DanmakuEpisodeInfo>> _loadDanmakuEpisodes(int animeId) async {
    final DanmakuService? svc = _danmakuService;
    if (svc == null) return const <DanmakuEpisodeInfo>[];
    return svc.fetchEpisodes(animeId);
  }

  /// 选定分集 → 拉取该集弹幕并替换当前轨道（对齐 iOS 手动指定弹幕源）。
  Future<void> _selectDanmakuEpisode(DanmakuEpisodeInfo episode) async {
    final DanmakuService? svc = _danmakuService;
    if (svc == null) return;
    final List<DanmakuItem> items =
        await svc.fetchByEpisodeId(episode.episodeId);
    if (!mounted) return;
    setState(() {
      _danmakuItems = items;
      _danmakuEpisodeId = episode.episodeId;
      _danmakuStates = const <DanmakuRenderState>[];
    });
    _syncDanmakuController();
    _toast(items.isEmpty ? '该集暂无弹幕' : '已加载弹幕（${items.length} 条）');
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
    // 调试浮层（UI-F6 工具菜单开关；契约键 `show_debug_overlay`）。
    bool debugOverlay = false;
    try {
      debugOverlay = await PrefsManager.instance.getBool('show_debug_overlay');
    } catch (_) {
      // 未初始化存储（如单测）→ 保持关闭。
    }
    // 片头片尾设置（UI-F2；按视频独立加载）。
    SkipSettings skip = const SkipSettings();
    try {
      skip = await SkipSettings.load(widget.vodId);
    } catch (_) {
      // 读取失败 → 全关。
    }
    if (!mounted) return;
    setState(() {
      _playback = s;
      _skipSettings = skip;
      _autoPlayNext.enabled = s.autoPlayNext;
      _longPressSpeed.updateSpeed(s.longPressSpeed);
      _controls.pipAvailable = s.pipEnabled;
      // UI-F6 工具菜单开关回填
      _controls
        ..autoPlayNext = s.autoPlayNext
        ..backgroundPlay = s.backgroundPlay
        ..pipEnabled = s.pipEnabled
        ..debugOverlay = debugOverlay
        ..longPressSpeed = s.longPressSpeed
        // UI-F2 片头片尾
        ..skipIntroEnabled = skip.introEnabled
        ..skipIntroSeconds = skip.introSeconds
        ..skipOutroEnabled = skip.outroEnabled
        ..skipOutroSeconds = skip.outroSeconds;
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
    // UI-F22：前后台恢复保护（对齐 iOS `handleSceneBackground` /
    // `handleSceneForeground`；iOS 把 `.background` 与 `.inactive` 一并视为退后台）。
    if (lifecycle == PlaybackLifecycle.background) {
      _handleEnterBackground();
    } else {
      _handleEnterForeground();
    }
  }

  // ─────────────── 前后台恢复保护（UI-F22）───────────────

  /// 进入后台（对齐 iOS `handleSceneBackground`）。
  ///
  /// 未开启后台播放 → 暂停播放器（防后台耗电 / 越权播放）并**强制落库进度**；
  /// 开启后台播放 → 保持播放（音频续播，由 C-05 后台承载负责）。
  void _handleEnterBackground() {
    _foregroundRestoreTimer?.cancel();
    _foregroundRestoreTimer = null;
    if (!_playback.backgroundPlay && _controls.isPlaying) {
      _pausedForBackground = true;
      unawaited(_player.pause());
    }
    // 退后台即强制落库（跳过 5s 节流，保留 >5s 与看完清除守卫）。
    _persistProgress(
      _controls.positionMs,
      _controls.durationMs,
      throttle: false,
    );
  }

  /// 回到前台（对齐 iOS `handleSceneForeground`）：**800ms 宽限**后恢复播放。
  ///
  /// 仅恢复「因退后台被自动暂停」的播放（用户主动暂停的不在此列，比 iOS 更保守）。
  void _handleEnterForeground() {
    _foregroundRestoreTimer?.cancel();
    _foregroundRestoreTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted || !_pausedForBackground) return;
      _pausedForBackground = false;
      unawaited(_player.play());
    });
  }

  /// 「更多 → 画中画」：进入 / 退出画中画。
  Future<void> _togglePip() async {
    final PipController? pip = _pip;
    if (pip == null) return;
    try {
      if (pip.isInPip) {
        await pip.exit();
      } else {
        // UI-B1 触感反馈：对齐 iOS 启动画中画时的 medium 震动。
        unawaited(HapticFeedback.mediumImpact());
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
        _controls.subtitleFileName = _subtitleDisplayName(uri);
      });
      _toast('字幕已加载（${cues.length} 条）');
    } catch (_) {
      if (mounted) _toast('字幕加载失败');
    }
  }

  /// 字幕显示名（URL 末段；对齐 iOS `subtitleFileName`）。
  static String _subtitleDisplayName(Uri uri) {
    final List<String> segments = uri.pathSegments;
    return segments.isEmpty ? uri.toString() : segments.last;
  }

  /// 清除已加载字幕（UI-F5 字幕设置面板）。
  void _clearSubtitle() {
    if (_subtitleTrack == null && _controls.subtitleFileName.isEmpty) return;
    setState(() {
      _subtitleTrack = null;
      _subtitleCueText = null;
      _controls.subtitleFileName = '';
    });
    _toast('已清除字幕');
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
    // UI-B1 触感反馈：对齐 iOS `startLongPressSpeed` 的 medium 震动。
    unawaited(HapticFeedback.mediumImpact());
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
    // UI-F16：进度读取与起播**并行**（续播在首帧就绪时才应用，无需阻塞起播）。
    unawaited(_loadResumePosition());
    await _openSource(widget.source);
    _scheduleHide();
  }

  // ─────────────── 进度续播（UI-F16 + F-P15 按集独立）───────────────

  /// 读取该视频指定集的上次进度；命中恢复守卫（>10s）则记为待续播位置。
  ///
  /// 键按集独立（对齐 iOS `playbackProgressKey` 的 `v2_<vodId>_<episodeIndex>`）；
  /// 读取失败（存储未初始化等）→ 不续播，不阻断播放。若首帧已就绪（存储读取
  /// 晚于首个进度事件）→ 立即补应用（[_applyResumeIfNeeded] 幂等）。
  Future<void> _loadResumePosition({int? episodeIndex}) async {
    if (widget.vodId.isEmpty) return;
    final int idx = episodeIndex ?? widget.initialEpisodeIndex;
    double saved = 0;
    try {
      saved = await PlaybackProgressStore.load(widget.vodId, episodeIndex: idx);
    } catch (_) {
      return;
    }
    if (!PlaybackProgressStore.shouldResume(saved)) return;
    _resumePositionMs = saved * 1000;
    _applyResumeIfNeeded();
  }

  /// 首帧就绪后应用一次续播 seek（幂等；切集复位后可再次应用）。
  void _applyResumeIfNeeded() {
    final double? target = _resumePositionMs;
    if (_resumeApplied || target == null || target <= 0) return;
    _resumeApplied = true;
    unawaited(_player.seekTo(target.round()));
  }

  /// 按 iOS 口径落库进度：`> 5s` 才存、距结尾 `< 15s` 视为看完清除。
  ///
  /// 键按当前集独立（对齐 iOS `savePlaybackProgress` 以 `currentEpisodeIndex`
  /// 算键）。[throttle] 为 true 时套用 5s 节流（播放中进度事件）；为 false 时
  /// 强制落库（退后台等关键切换点，对齐 iOS `handleSceneBackground` 的强制保存）。
  void _persistProgress(
    int positionMs,
    int durationMs, {
    required bool throttle,
  }) {
    if (widget.vodId.isEmpty || durationMs <= 0) return;
    final double seconds = positionMs / 1000.0;
    if (!PlaybackProgressStore.shouldSave(seconds)) return;
    if (PlaybackProgressStore.isNearEnd(seconds, durationMs / 1000.0)) {
      unawaited(
        PlaybackProgressStore.clear(
          widget.vodId,
          episodeIndex: _controls.currentEpisodeIndex,
        ),
      );
      return;
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (throttle) {
      if (now - _lastProgressSaveMs < PlaybackProgressStore.saveThrottleMs) {
        return;
      }
    }
    _lastProgressSaveMs = now;
    unawaited(
      PlaybackProgressStore.save(
        widget.vodId,
        seconds,
        episodeIndex: _controls.currentEpisodeIndex,
      ),
    );
  }

  /// 播放中进度事件 → 节流落库。
  void _saveProgressThrottled(PlaybackProgress p) {
    _persistProgress(p.positionMs, p.durationMs, throttle: true);
  }

  // ─────────────── 下一集预取（UI-F17）───────────────

  /// 剩余时长进入阈值（30s）时预取下一集直链。
  ///
  /// 每集仅触发一次（[`_preloadedEpisodeIndex`] / [`_preloadingIndex`] 双守卫）；
  /// 无解析器 / 无下一集 / 时长未知 → 不预取。
  void _maybePreloadNextEpisode(PlaybackProgress p) {
    if (widget.onResolveEpisode == null || p.durationMs <= 0) return;
    if (p.durationMs - p.positionMs > _preloadRemainMs) return;
    final int next = _controls.currentEpisodeIndex + 1;
    if (next >= widget.episodes.length) return;
    if (_preloadedEpisodeIndex == next || _preloadingIndex == next) return;
    _preloadingIndex = next;
    unawaited(_preloadEpisode(next));
  }

  /// 预取指定集解析结果并缓存（失败静默降级，不影响当前播放）。
  Future<void> _preloadEpisode(int index) async {
    final EpisodeSourceResolver? resolver = widget.onResolveEpisode;
    if (resolver == null) return;
    try {
      final PlayerSource? source = await resolver(widget.episodes[index]);
      if (!mounted || source == null) return;
      // 期间已切集 → 丢弃（缓存只服务于「当前集的下一集」）。
      if (_controls.currentEpisodeIndex + 1 != index) return;
      _preloadedEpisodeIndex = index;
      _preloadedSource = source;
    } catch (_) {
      // 预取失败 → 不缓存，切集时按常规重新解析。
    } finally {
      if (_preloadingIndex == index) _preloadingIndex = null;
    }
  }

  // ─────────────── 片头片尾跳过（UI-F2）───────────────

  /// 按设置跳过片头 / 片尾（对齐 iOS 播放中两处判定；一集内各触发一次）。
  ///
  /// 直播流不适用；片头命中即 seek 到片头结束，片尾命中即推进下一集。
  void _applySkipSettings(PlaybackProgress p) {
    if (p.isLive) return;
    if (SkipTrigger.shouldSkipIntro(
      positionMs: p.positionMs,
      settings: _skipSettings,
      alreadyTriggered: _skipIntroTriggered,
    )) {
      _skipIntroTriggered = true;
      unawaited(_player.seekTo(_skipSettings.introSeconds * 1000));
      return;
    }
    if (SkipTrigger.shouldSkipOutro(
      positionMs: p.positionMs,
      durationMs: p.durationMs,
      settings: _skipSettings,
      alreadyTriggered: _skipOutroTriggered,
    )) {
      _skipOutroTriggered = true;
      unawaited(_advanceNext());
    }
  }

  // ─────────────── 视频区手势（UI-F1）───────────────

  /// 屏幕控制桥：移动端走原生通道，桌面走进程内会话实现（原生接线归平台批次）。
  ScreenControlsBridge _createScreenControlsBridge() =>
      (Platform.isAndroid || Platform.isIOS)
          ? MethodChannelScreenControlsBridge()
          : SessionScreenControlsBridge();

  /// 手势开始：记录起点快照（横竖形态决定是否允许横滑 seek）。
  ///
  /// 面板打开或方向锁定时禁用（对齐 iOS `isAnyPopupPresented` 守卫）：
  /// 传入零视口使状态机整体 no-op。
  void _onGestureStart(Offset localPosition) {
    final Size size = MediaQuery.sizeOf(context);
    final bool blocked =
        _controls.hasAnyPanelOpen || _controls.orientationLocked;
    _gestureTranslation = Offset.zero;
    _gestures.begin(
      localPosition: localPosition,
      viewport: blocked ? Size.zero : size,
      landscape: size.width > size.height,
      positionMs: _controls.positionMs,
      durationMs: _controls.durationMs,
    );
  }

  /// 手势推进：按模式刷新亮度 / 音量 / 进度预览，并更新提示浮层。
  Future<void> _onGestureUpdate(Offset delta) async {
    _gestureTranslation += delta;
    final GestureAdjustment? adj = await _gestures.update(_gestureTranslation);
    if (!mounted) return;
    if (adj == null) return;
    // seek 模式：拖动中实时回显进度（对齐 iOS `playerState.currentTime = target`）。
    if (adj.mode == GestureMode.seek) _controls.previewSeek(_gestures.seekTargetMs);
    setState(() => _gestureHud = adj);
  }

  /// 手势结束：seek 模式提交跳转；隐藏提示浮层。
  void _onGestureEnd() {
    final int? seekMs = _gestures.end();
    if (seekMs != null) _controls.onSeek?.call(seekMs);
    if (mounted && _gestureHud != null) setState(() => _gestureHud = null);
  }

  // ─────────────── 播放器接线 ───────────────

  void _bindPlayer() {
    _player.onStateChanged = (PlayerState s) {
      if (!mounted) return;
      _controls.updatePlaying(s == PlayerState.playing);
      // UI-D2：屏幕常亮按播放状态驱动（对齐 iOS `updateIdleTimer()` 收口：
      // 播放中 `isIdleTimerDisabled = true`；暂停 / 停止 / 结束显式恢复，
      // iOS 注释——后台场景系统可能重置 idle timer，故每次状态变化都同步）。
      unawaited(s == PlayerState.playing
          ? _wakeLock.enable()
          : _wakeLock.disable());
      // UI-F18：进入播放即收起加载层（首帧已就绪）。
      if (s == PlayerState.playing) {
        // UI-F21：首帧就绪 → 取消首帧超时兜底任务（对齐 iOS readyToPlay）。
        _markFirstFrameReady();
        _controls.hideLoading();
      }
      // C-05 自动连播：由控制器按开关决定是否推进下一集。
      _autoPlayNext.handleState(s);
    };
    _player.onProgress = (PlaybackProgress p) {
      if (!mounted) return;
      // UI-F18：跳转加载的进度回执 → 收起加载层（对齐 iOS seek 完成回调）。
      if (_seekLoadingPending) {
        _seekLoadingPending = false;
        _seekLoadingTimer?.cancel();
        _controls.hideLoading();
      }
      // UI-F16：首个进度事件即视为首帧就绪 → 应用续播 + 节流落库进度。
      _applyResumeIfNeeded();
      _saveProgressThrottled(p);
      // UI-F17：近结尾预取下一集直链。
      _maybePreloadNextEpisode(p);
      _controls.updateProgress(
        positionMs: p.positionMs,
        durationMs: p.durationMs,
        bufferedMs: p.bufferedMs,
        isLive: p.isLive,
      );
      _updateSubtitleCue(p.positionMs);
      // UI-F2：片头片尾自动跳过。
      _applySkipSettings(p);
      // 弹幕时基同步（定时器在两次进度事件间按墙钟插值）。
      _danmakuPosMs = p.positionMs;
      _danmakuSyncAtMs = DateTime.now().millisecondsSinceEpoch;
      final PipController? pip = _pip;
      if (pip != null && pip.isInPip) {
        unawaited(pip.updateProgress(p.positionMs, p.durationMs));
      }
      // 观看记录：详情页经此回调按节流落库（对齐 iOS 进度落库）。
      widget.onProgress?.call(p);
    };
    _player.onVideoSize = (int width, int height) {
      if (!mounted) return;
      // UI-F18：首帧尺寸上报 → 收起加载层（对齐 iOS 首帧就绪）。
      _controls.hideLoading();
      // UI-F21：首帧就绪 → 取消首帧超时兜底任务（对齐 iOS readyToPlay）。
      _markFirstFrameReady();
      // UI-F16：首帧就绪 → 应用续播 seek。
      _applyResumeIfNeeded();
      setState(() => _aspectRatio = width / height);
    };
    _player.onSurfaceChanged = (int? id) {
      if (!mounted) return;
      setState(() => _textureId = id);
    };
    _player.onError = (String message, {required bool fatal}) {
      if (!mounted) return;
      _appendLog('错误：$message');
      // 致命错误 → 覆盖错误态视图（可重试）；非致命仅提示（对齐 iOS 分级）。
      if (fatal) {
        // UI-F21：运行期原画 403 / 断连 → 优先切兜底线路（对齐 iOS `.failed` /
        // `AVPlayerItemFailedToPlayToEndTime` 分支）；打开期错误由 [_openSource]
        // 的 catch 统一收口，此处不重复触发。
        if (!_openingInFlight) {
          unawaited(_tryPanFallbackForText(message).then((bool switched) {
            if (!switched && mounted) setState(() => _errorMessage = message);
          }));
          return;
        }
        setState(() => _errorMessage = message);
      } else {
        _toast(message);
      }
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
      // UI-F18：跳转期间显示加载层，3s 安全超时兜底（对齐 iOS seekTimeoutTask）。
      _seekLoadingPending = true;
      _controls.showLoading(
        PlayerControlsController.loadingSeeking(
          PlayerControlsController.formatTime(ms),
        ),
      );
      _seekLoadingTimer?.cancel();
      _seekLoadingTimer = Timer(const Duration(seconds: 3), () {
        _seekLoadingPending = false;
        if (mounted) _controls.hideLoading();
      });
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
    // ── UI-F6 工具菜单开关（持久化到契约键）──
    _controls.onToggleAutoPlayNext = (bool v) {
      _autoPlayNext.enabled = v;
      unawaited(_savePref('player_auto_play_next', v));
    };
    _controls.onToggleBackgroundPlay = (bool v) {
      final BackgroundPlayController? bg = _backgroundPlay;
      if (bg != null) bg.enabled = v;
      unawaited(_savePref('player_background_play', v));
    };
    _controls.onTogglePipEnabled = (bool v) {
      _controls.pipAvailable = v;
      unawaited(_savePref('player_pip_enabled', v));
    };
    _controls.onToggleDebugOverlay = (bool v) {
      unawaited(_savePref('show_debug_overlay', v));
    };
    // ── UI-F6 → 长按倍速（S-07：即时生效 + 持久化）──
    _controls.onSelectLongPressSpeed = (double v) {
      _longPressSpeed.updateSpeed(v);
      unawaited(_savePref('player_long_press_speed', v));
      if (mounted) setState(() {});
    };
    // ── UI-F2 片头片尾（按视频独立持久化）──
    _controls.onSkipSettingsChanged = (SkipSettings v) {
      _skipSettings = v;
      _skipIntroTriggered = false;
      _skipOutroTriggered = false;
      unawaited(v.save(widget.vodId));
    };
    // ── UI-F5 字幕样式 ──
    _controls.onSubtitleStyleChanged = (SubtitleStyle v) {
      if (mounted) setState(() {});
    };
    _controls.onClearSubtitle = _clearSubtitle;
  }

  /// 写单个契约键（未初始化存储 / 契约外键时静默忽略，不阻断播放）。
  Future<void> _savePref(String key, Object value) async {
    try {
      await PrefsManager.instance.set(key, value);
    } catch (_) {
      // 忽略：偏好写入失败不影响本次播放会话。
    }
  }

  /// 打开播放源并起播；失败抛 [PlayerOpenException] 已在导航层处理，此处仅提示。
  ///
  /// [preparePanFallback] 为 true 时按源装载网盘兜底链并启动首帧超时（UI-F21）；
  /// 兜底线路重开时传 false，保留 `attempted` 标记防重复切换。
  ///
  /// 首开后端不支持时按两条既有能力补救（C-07 / C-12）：
  ///  1. UI-F21：原画线路 403 / 断连 → 先切 m3u8 兜底线路（对齐 iOS 判据顺序）；
  ///  2. 复杂封装（MKV / FLV / TS…）经转封装代理换 fMP4 容器重试一次；
  ///  3. 仍失败则探测直链可达性，给出精确诊断（地址不可达 vs 地址不可用）。
  Future<void> _openSource(
    PlayerSource source, {
    bool preparePanFallback = true,
  }) async {
    if (preparePanFallback) {
      _configurePanFallback(source);
      _scheduleFirstFrameFallbackTimeout();
    }
    _firstFrameReady = false;
    _openingInFlight = true;
    // UI-F18：解析 / 打开期间显示加载层（首帧就绪后由 onVideoSize 收起）。
    _controls.showLoading();
    try {
      await _player.open(source, route: widget.route);
      await _player.play();
      if (!mounted) return;
      _controls.currentBackend = _player.backend;
      // 起播成功 → 退出错误态（重试成功即收起重试视图）。
      if (_errorMessage != null) setState(() => _errorMessage = null);
    } on PlayerOpenException catch (e) {
      _appendLog('打开失败：${e.code} ${e.message}');
      // UI-F21：原画线路 403 / 断连 → 先切兜底线路（已接管则直接返回）。
      if (await _tryPanFallbackForText('${e.code} ${e.message}')) return;
      final PlayerSource? remuxed = await _remuxFallback(source);
      if (remuxed != null) {
        try {
          await _player.open(remuxed, route: widget.route);
          await _player.play();
          if (!mounted) return;
          _controls.currentBackend = _player.backend;
          if (_errorMessage != null) setState(() => _errorMessage = null);
          return;
        } on PlayerOpenException {
          // 转封装后仍失败 → 走下方统一诊断提示。
        }
      }
      final String message = await _diagnose(e, source);
      _controls.hideLoading();
      _showError(message);
    } finally {
      _openingInFlight = false;
    }
  }

  // ─────────────── 网盘兜底链（UI-F21）───────────────

  /// 按播放源装载兜底链（对齐 iOS `playResolvedDriveVideo` 装载 `quarkFallback*`
  /// 语义：每次装载重置 `attempted`）。
  void _configurePanFallback(PlayerSource source) {
    _panFallbackTimeout?.cancel();
    _panFallbackTimeout = null;
    if (!source.hasFallback) {
      _panFallback = null;
      return;
    }
    _panFallback = PanFallbackChain(
      fallback: PanPlaybackLine(
        url: source.fallbackUrl!,
        headers: source.fallbackHeaders,
        source: source.fallbackSource,
        useQuarkProxy: source.fallbackUseQuarkProxy,
      ),
    );
  }

  /// 原画线路首帧超时任务（对齐 iOS `scheduleQuarkPrimaryFallbackTimeout`）。
  ///
  /// 仅当存在可用兜底线路时启动；8s 后仍未出画（[_firstFrameReady] 为 false）→
  /// 以「首帧超时」原因切兜底（对齐 iOS `quarkFallbackTimeoutTask` 的 8s）。
  void _scheduleFirstFrameFallbackTimeout() {
    _panFallbackTimeout?.cancel();
    _panFallbackTimeout = null;
    final PanFallbackChain? chain = _panFallback;
    if (chain == null || !chain.available) return;
    _panFallbackTimeout = Timer(PanFallbackChain.firstFrameTimeout, () {
      if (!mounted || _firstFrameReady) return;
      final PanFallbackChain? c = _panFallback;
      if (c == null || !c.available) return;
      _appendLog('原画线路首帧超时，切换兜底线路');
      unawaited(_tryPanFallback(PanFallbackTrigger.firstFrameTimeout));
    });
  }

  /// 首帧就绪：取消首帧超时任务（对齐 iOS readyToPlay 取消 `quarkFallbackTimeoutTask`）。
  void _markFirstFrameReady() {
    if (_firstFrameReady) return;
    _firstFrameReady = true;
    _panFallbackTimeout?.cancel();
    _panFallbackTimeout = null;
  }

  /// 屏幕拉伸循环切换（UI-E2，对齐 iOS `cycleVideoGravity()`）：
  /// 填充 → 适应 → 拉伸 → 填充（声明序取模）。
  void _cycleVideoGravity() {
    setState(() => _videoGravity = _videoGravity.cycle());
  }

  /// 按错误文案归类并尝试切换网盘兜底线路（UI-F21）。
  Future<bool> _tryPanFallbackForText(String text) async {
    final PanFallbackTrigger? trigger = PanFallbackChain.classifyFailure(text);
    if (trigger == null) return false;
    return _tryPanFallback(trigger);
  }

  /// 切换网盘兜底线路并重开播放（对齐 iOS `switchToQuarkFallback(reason:)`）。
  ///
  /// 仅当存在可用兜底线路且**尚未尝试过**时切换（[PanFallbackChain.claim]，对齐
  /// iOS `quarkFallbackAttempted`）；返回 true 表示已接管（调用方不应再展示错误视图）。
  Future<bool> _tryPanFallback(PanFallbackTrigger trigger) async {
    final PanFallbackChain? chain = _panFallback;
    if (chain == null || !chain.claim(trigger)) return false;
    _panFallbackTimeout?.cancel();
    _panFallbackTimeout = null;
    final PanPlaybackLine line = chain.fallback!;
    _appendLog('切换网盘兜底线路：${trigger.reason} → ${line.effectiveSource}');
    // 兜底线路经 Go 代理落地（HLS / 夸克原画注入鉴权头；代理不可用降级直链）。
    // provider 沿当前盘透传（F-P28：同盘切集 provider 不变，兜底重开维持按盘策略）。
    final PlayerSource fallbackSource = await resolvePanPlaybackLine(
      line,
      title: widget.title,
      provider: widget.source.provider,
    );
    if (!mounted) return true;
    // 重开兜底源（不重置兜底链，保持 `attempted = true` 防重复切换）。
    await _openSource(fallbackSource, preparePanFallback: false);
    return true;
  }

  /// 记录播放器日志（错误态调试查看；仅保留最近 200 条，防无界增长）。
  void _appendLog(String line) {
    _playerLogs.add('${DateTime.now().toIso8601String()} $line');
    if (_playerLogs.length > 200) _playerLogs.removeAt(0);
  }

  /// 进入错误态（覆盖视图 + 记录日志；对齐 iOS `ErrorViewWithLogs`）。
  void _showError(String message) {
    _appendLog('加载失败：$message');
    if (!mounted) return;
    setState(() => _errorMessage = message);
  }

  /// 退出错误态并重试当前源（对齐 iOS `ErrorView.onRetry`）。
  Future<void> _retry() async {
    if (!mounted) return;
    setState(() => _errorMessage = null);
    _showControls();
    await _openSource(widget.source);
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
    // UI-F18：切换内核期间显示加载层（对齐 iOS `正在切换 \(engineName)...`）。
    _controls.showLoading(
      PlayerControlsController.loadingSwitchingEngine(backend.shortName),
    );
    try {
      await _player.switchBackend(backend);
      if (!mounted) return;
      _controls.currentBackend = _player.backend;
    } catch (_) {
      // 切换失败 → 收起加载层，不误报（错误经 onError 分类呈现）。
      if (mounted) _controls.hideLoading();
    }
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
    // UI-F18：切换集数期间显示加载层（对齐 iOS `正在解析播放地址...`）。
    _controls.showLoading();
    // UI-F17：命中预取缓存 → 跳过二次解析（切集即时起播）。
    final PlayerSource? preloaded =
        _preloadedEpisodeIndex == index ? _preloadedSource : null;
    _preloadedEpisodeIndex = null;
    _preloadedSource = null;
    final PlayerSource? source = preloaded ?? await resolver(episode);
    if (!mounted) return;
    if (source == null) {
      _controls.hideLoading();
      return;
    }
    // F-P15：切集 → 复位续播标记并恢复**该集**进度（对齐 iOS
    // `switchToEpisode` L5970-5976「重置当前时间 + restorePlaybackProgress」）。
    _resumePositionMs = null;
    _resumeApplied = false;
    unawaited(_loadResumePosition(episodeIndex: index));
    await _openSource(source);
    // 切集 → 重新拉取该集弹幕并重置进度时基。
    _danmakuPosMs = 0;
    _danmakuSyncAtMs = DateTime.now().millisecondsSinceEpoch;
    unawaited(_loadDanmakuItems());
    // 切集 → 片头片尾触发标记复位（对齐 iOS `loadSkipSettings` 语义）。
    _skipIntroTriggered = false;
    _skipOutroTriggered = false;
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
    _seekLoadingTimer?.cancel();
    _foregroundRestoreTimer?.cancel();
    _panFallbackTimeout?.cancel();
    _danmakuTimer?.cancel();
    // UI-D2：退出播放页兜底恢复锁屏（对齐 iOS dismiss 后内核 stop 恢复 idle timer；
    // 常规路径 pause 已触发 disable，此处防控制器状态回调丢失）。
    unawaited(_wakeLock.disable());
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
          // UI-F1 视频区手势：横滑快进快退 / 左半屏纵滑亮度 / 右半屏纵滑音量。
          onPanStart: (DragStartDetails d) => _onGestureStart(d.localPosition),
          onPanUpdate: (DragUpdateDetails d) =>
              unawaited(_onGestureUpdate(d.delta)),
          onPanEnd: (DragEndDetails _) => _onGestureEnd(),
          onPanCancel: _gestures.cancel,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              PlayerControlsView(
                controller: _controls,
                lockButtonVisible: _lockButtonVisible,
                controlsVisible: _controlsVisible,
                danmakuSettings: _danmaku,
                onDanmakuSettingsChanged: _onDanmakuChanged,
                danmakuSearch: _searchDanmakuAnime,
                danmakuLoadEpisodes: _loadDanmakuEpisodes,
                onSelectDanmakuEpisode: (DanmakuEpisodeInfo e) =>
                    unawaited(_selectDanmakuEpisode(e)),
                // UI-E2：屏幕拉伸（对齐 iOS 顶栏「屏幕拉伸」按钮循环切换）。
                videoGravity: _videoGravity,
                onCycleVideoGravity: _cycleVideoGravity,
                videoBuilder: (BuildContext context) => VideoSurface(
                  textureId: _textureId,
                  aspectRatio: _aspectRatio,
                  // UI-E2：画面拉伸模式（填充 / 适应 / 拉伸）。
                  fit: switch (_videoGravity) {
                    VideoGravityMode.aspectFill => BoxFit.cover,
                    VideoGravityMode.aspectFit => BoxFit.contain,
                    VideoGravityMode.resize => BoxFit.fill,
                  },
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
              // C-08 字幕浮层（随时间更新；不拦截手势；样式随 UI-F5 设置）。
              if (_controls.showSubtitle &&
                  _subtitleCueText != null &&
                  _subtitleCueText!.isNotEmpty)
                _SubtitleOverlay(
                  text: _subtitleCueText!,
                  style: _controls.subtitleStyle,
                ),
              // UI-F1 手势提示浮层（亮度 / 音量 / 快进快退）。
              if (_gestureHud != null)
                PlayerGestureHud(adjustment: _gestureHud!),
              // C-05 长按倍速提示浮层。
              if (_longPressSpeedActive)
                _LongPressSpeedOverlay(text: _controls.speedDisplayText),
              // UI-F10 错误态 / 重试视图（覆盖全屏；含可展开调试日志）。
              if (_errorMessage != null)
                Positioned.fill(
                  child: PlayerErrorWithLogsView(
                    message: _errorMessage!,
                    logs: _playerLogs,
                    onRetry: () => unawaited(_retry()),
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 字幕浮层（画面下方居中；对齐 iOS `currentSubtitleText` 叠加）。
///
/// 样式随 UI-F5 字幕设置（字号 / 颜色）实时变化。
class _SubtitleOverlay extends StatelessWidget {
  const _SubtitleOverlay({required this.text, required this.style});

  final String text;

  /// 当前字幕样式（字号 / 颜色）。
  final SubtitleStyle style;

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
          style: TextStyle(
            color: VboxColors.subtitleColorAt(style.colorIndex),
            fontSize: style.fontSize,
            fontWeight: FontWeight.w600,
            height: 1.3,
            shadows: const <Shadow>[
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