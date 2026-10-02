/// 表现层：播放器控制层视图状态（批次 C · C-02 / C-04）。
///
/// 纯 UI 状态容器：只承载「当前播放状态 + 面板开关 + 选择项」，动作经回调
/// 字段上抛（调用方接线到 [PlayerController] 与业务回调）。`ChangeNotifier`
/// 供 [AnimatedBuilder] / `ListenableBuilder` 刷新。
///
/// 对齐 iOS `PlayerState`（ObservableObject）在控制层的语义子集：
/// 播放/暂停 · 进度 · 倍速 · 清晰度 · 选集 · 内核 · 弹幕开关 · 面板互斥开关。
library;

import 'package:flutter/material.dart';

import '../../../domain/entities/player/player.dart';
import '../../../domain/entities/playback/playback_detail.dart';
import '../../ui_mode/ui_mode.dart';

/// 播放器控制层视图状态。
class PlayerControlsController extends ChangeNotifier {
  /// 构造（缺省为「未开播」初始态）。
  PlayerControlsController({
    this.title,
    this.subtitle,
    this.form = UiForm.portrait,
    this.isPlaying = false,
    this.isFullscreen = false,
    this.positionMs = 0,
    this.durationMs = 0,
    this.bufferedMs = 0,
    this.isLive = false,
    this.speed = 1.0,
    this.qualities = const <String>[],
    this.selectedQuality = 0,
    this.episodes = const <PlaybackEpisode>[],
    this.currentEpisodeIndex = 0,
    this.backends = const <PlayerBackend>[],
    this.currentBackend,
    this.showDanmaku = false,
    this.hasDanmaku = false,
  });

  // ── 标题区 ───────────────────────────────────────────

  /// 主标题（剧名）。
  String? title;

  /// 副标题（如「第 3 集 · 默认源」）。
  String? subtitle;

  // ── 形态与播放状态 ───────────────────────────────────

  /// 显示形态（横 / 竖；决定底栏与面板布局）。
  UiForm form;

  /// 是否播放中。
  bool isPlaying;

  /// 是否全屏（决定是否显示顶栏「退出全屏」等）。
  bool isFullscreen;

  /// 当前进度（毫秒）。
  int positionMs;

  /// 总时长（毫秒；直播或未知为 0）。
  int durationMs;

  /// 缓冲进度（毫秒）。
  int bufferedMs;

  /// 是否直播流（隐藏拖拽 / 显示直播态）。
  bool isLive;

  // ── 倍速 / 清晰度 / 选集 / 内核 ──────────────────────

  /// 当前倍速。
  double speed;

  /// 可选清晰度文案（如 `标清/高清/蓝光`；空表不可用）。
  List<String> qualities;

  /// 当前清晰度索引。
  int selectedQuality;

  /// 剧集列表。
  List<PlaybackEpisode> episodes;

  /// 当前剧集索引。
  int currentEpisodeIndex;

  /// 可用内核列表（当前端降级链）。
  List<PlayerBackend> backends;

  /// 当前内核（null 表示未开播）。
  PlayerBackend? currentBackend;

  // ── 弹幕 ─────────────────────────────────────────────

  /// 弹幕显示开关（会话级）。
  bool showDanmaku;

  /// 该源是否具备弹幕（无弹幕源时隐藏弹幕按钮）。
  bool hasDanmaku;

  // ── 面板开关（互斥：同屏至多一个）────────────────────

  bool _showEpisodePicker = false;
  bool _showQualityPicker = false;
  bool _showSpeedPicker = false;
  bool _showEnginePicker = false;
  bool _showDanmakuSettings = false;
  bool _showToolsMenu = false;

  // ── 动作回调（调用方接线；null 表示不可用/禁用）──────

  VoidCallback? onTogglePlay;
  VoidCallback? onPrevEpisode;
  VoidCallback? onNextEpisode;
  VoidCallback? onToggleFullscreen;
  VoidCallback? onBack;
  VoidCallback? onCast;
  VoidCallback? onToggleDanmaku;
  VoidCallback? onToggleDanmakuSettings;
  VoidCallback? onToggleToolsMenu;
  VoidCallback? onToggleOrientationLock;

  /// 进度拖拽结束回调（毫秒）。
  void Function(int positionMs)? onSeek;

  /// 选集回调（索引）。
  void Function(int index)? onSelectEpisode;

  /// 清晰度回调（索引）。
  void Function(int index)? onSelectQuality;

  /// 倍速回调。
  void Function(double speed)? onSelectSpeed;

  /// 内核回调。
  void Function(PlayerBackend backend)? onSelectBackend;

  // ── 只读派生 ─────────────────────────────────────────

  /// 进度百分比（0.0 ~ 1.0；直播 / 未知时长恒 0）。
  double get progress {
    if (isLive || durationMs <= 0) return 0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  /// 缓冲百分比（0.0 ~ 1.0）。
  double get buffered {
    if (isLive || durationMs <= 0) return 0;
    return (bufferedMs / durationMs).clamp(0.0, 1.0);
  }

  /// 倍速显示文案（如 `1.0x` / `1.25x`；尾零裁剪）。
  String get speedDisplayText {
    final String s = speed.toStringAsFixed(2);
    final String trimmed = s.endsWith('.00')
        ? s.substring(0, s.length - 3)
        : s.endsWith('0')
            ? s.substring(0, s.length - 1)
            : s;
    return '${trimmed}x';
  }

  /// 当前清晰度文案（无可用清晰度时回「默认」）。
  String get qualityDisplayText {
    if (qualities.isEmpty) return '默认';
    final int i = selectedQuality.clamp(0, qualities.length - 1);
    return qualities[i];
  }

  /// 当前内核按钮文案（未开播显示「内核」）。
  String get backendDisplayText {
    final PlayerBackend? b = currentBackend;
    if (b == null) return '内核';
    return switch (b) {
      PlayerBackend.media3 => 'Media3',
      PlayerBackend.libVLC => 'VLC',
      PlayerBackend.libmpv => 'MPV',
      PlayerBackend.nativeiOS => '原生',
    };
  }

  /// 当前播放位置时间文案（`HH:MM:SS` / `MM:SS`）。
  String get positionText => _formatTime(positionMs);

  /// 总时长时间文案（未知时长显示 `--:--`）。
  String get durationText => durationMs <= 0 ? '--:--' : _formatTime(durationMs);

  /// 是否有上一集 / 下一集。
  bool get hasPrevEpisode => currentEpisodeIndex > 0;
  bool get hasNextEpisode =>
      currentEpisodeIndex >= 0 && currentEpisodeIndex < episodes.length - 1;

  /// 是否有可用清晰度。
  bool get hasQuality => qualities.isNotEmpty;

  /// 是否有可用内核。
  bool get hasBackend => backends.isNotEmpty;

  // ── 面板开关访问 ─────────────────────────────────────

  bool get showEpisodePicker => _showEpisodePicker;
  bool get showQualityPicker => _showQualityPicker;
  bool get showSpeedPicker => _showSpeedPicker;
  bool get showEnginePicker => _showEnginePicker;
  bool get showDanmakuSettings => _showDanmakuSettings;
  bool get showToolsMenu => _showToolsMenu;

  /// 是否任一面板打开（控制层据此隐藏自动消失逻辑）。
  bool get hasAnyPanelOpen =>
      _showEpisodePicker ||
      _showQualityPicker ||
      _showSpeedPicker ||
      _showEnginePicker ||
      _showDanmakuSettings ||
      _showToolsMenu;

  // ── 状态更新（调用方 / 播放器事件接线）────────────────

  /// 批量更新播放进度（对齐 iOS `PlayerProgress` 回调）。
  void updateProgress({
    required int positionMs,
    required int durationMs,
    int? bufferedMs,
    bool? isLive,
  }) {
    this.positionMs = positionMs;
    this.durationMs = durationMs;
    this.bufferedMs = bufferedMs ?? this.bufferedMs;
    this.isLive = isLive ?? this.isLive;
    notifyListeners();
  }

  /// 更新播放状态（对齐 iOS `PlayerState` 回调）。
  void updatePlaying(bool playing) {
    if (isPlaying == playing) return;
    isPlaying = playing;
    notifyListeners();
  }

  /// 设置形态（横竖切换时由调用方注入）。
  void setForm(UiForm form) {
    if (this.form == form) return;
    this.form = form;
    notifyListeners();
  }

  /// 选择剧集（先回调，失败由调用方回滚）。
  void selectEpisode(int index) {
    if (index < 0 || index >= episodes.length) return;
    currentEpisodeIndex = index;
    _showEpisodePicker = false;
    onSelectEpisode?.call(index);
    notifyListeners();
  }

  /// 选择清晰度。
  void selectQuality(int index) {
    if (index < 0 || index >= qualities.length) return;
    selectedQuality = index;
    _showQualityPicker = false;
    onSelectQuality?.call(index);
    notifyListeners();
  }

  /// 选择倍速。
  void selectSpeed(double value) {
    speed = value;
    _showSpeedPicker = false;
    onSelectSpeed?.call(value);
    notifyListeners();
  }

  /// 选择内核。
  void selectBackend(PlayerBackend backend) {
    if (!backends.contains(backend)) return;
    currentBackend = backend;
    _showEnginePicker = false;
    onSelectBackend?.call(backend);
    notifyListeners();
  }

  /// 切换播放 / 暂停（禁用态无回调时忽略）。
  void togglePlay() => onTogglePlay?.call();

  /// 上一集 / 下一集。
  void goPrevEpisode() => onPrevEpisode?.call();
  void goNextEpisode() => onNextEpisode?.call();

  // ── 面板互斥开关 ─────────────────────────────────────

  /// 打开选集面板（关闭其余面板）。
  void openEpisodePicker() => _openOnly(() => _showEpisodePicker = true);

  /// 打开清晰度面板。
  void openQualityPicker() => _openOnly(() => _showQualityPicker = true);

  /// 打开倍速面板。
  void openSpeedPicker() => _openOnly(() => _showSpeedPicker = true);

  /// 打开内核面板。
  void openEnginePicker() => _openOnly(() => _showEnginePicker = true);

  /// 打开弹幕设置面板。
  void openDanmakuSettings() => _openOnly(() => _showDanmakuSettings = true);

  /// 打开「更多」菜单。
  void openToolsMenu() => _openOnly(() => _showToolsMenu = true);

  /// 关闭全部面板。
  void closeAllPanels() {
    if (!hasAnyPanelOpen) return;
    _showEpisodePicker = false;
    _showQualityPicker = false;
    _showSpeedPicker = false;
    _showEnginePicker = false;
    _showDanmakuSettings = false;
    _showToolsMenu = false;
    notifyListeners();
  }

  void _openOnly(VoidCallback open) {
    final bool wasOpen = hasAnyPanelOpen;
    closeAllPanels();
    open();
    if (!wasOpen) notifyListeners();
  }

  // ── 内部工具 ─────────────────────────────────────────

  static String _formatTime(int ms) {
    final int totalSec = ms ~/ 1000;
    final int h = totalSec ~/ 3600;
    final int m = (totalSec % 3600) ~/ 60;
    final int s = totalSec % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}
