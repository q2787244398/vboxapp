/// 领域层：播放器抽象接口。
///
/// 唯一真相源：迁移计划 D6（播放器策略）+ `contract/schema/site_v1.json`
///   · Android：Media3（主）→ libVLC（全格式回退）
///   · Windows/macOS：libmpv
///   · iOS：不迁移（维持原生 AVPlayer/MDK/VLC 等 6 后端）
library;

/// 播放器后端类型（对齐 D6）。
enum PlayerBackend {
  /// Android 主播放器（Media3 / ExoPlayer）。
  media3,

  /// 全格式回退（libVLC）—— Android 必需。
  libVLC,

  /// 桌面播放器（libmpv，via media_kit）。
  libmpv,

  /// 全格式硬解内核（MDK SDK）—— 统一内核接缝。
  ///
  /// M1 仅交付 Dart 侧接缝（枚举 / 链路 / 面板 / 降级）；原生接入见 M2（Android）
  /// 与 M3（Windows / macOS）。原生未接入时 [open] 回 `E_BACKEND_UNAVAILABLE`，
  /// 由降级链自动改投下一后端，行为与未接入前一致。
  mdk,

  /// iOS 原生（不迁移，仅作契约对齐占位）。
  nativeiOS,
}

/// 后端能力元数据（P-芯6：显示名 / 系统 PiP 支持单点内聚，避免 UI 重复文案表）。
extension PlayerBackendMeta on PlayerBackend {
  /// 长显示名（内核选择面板）。
  String get displayName => switch (this) {
        PlayerBackend.media3 => 'Media3（系统播放器）',
        PlayerBackend.libVLC => 'libVLC（全格式）',
        PlayerBackend.libmpv => 'libmpv',
        PlayerBackend.mdk => 'MDK（全格式）',
        PlayerBackend.nativeiOS => '原生播放器',
      };

  /// 短显示名（播放控制条内核按钮）。
  String get shortName => switch (this) {
        PlayerBackend.media3 => 'Media3',
        PlayerBackend.libVLC => 'VLC',
        PlayerBackend.libmpv => 'MPV',
        PlayerBackend.mdk => 'MDK',
        PlayerBackend.nativeiOS => '原生',
      };

  /// 是否支持系统级画中画（对齐 PiP 策略的系统承载后端集合）。
  bool get supportsSystemPip => switch (this) {
        PlayerBackend.media3 => true,
        PlayerBackend.nativeiOS => true,
        PlayerBackend.libVLC => false,
        PlayerBackend.libmpv => false,
        PlayerBackend.mdk => false,
      };
}

/// 播放模式（对齐 `site_v1.json` 的 `playMode`）。
enum PlayMode {
  /// 普通直链播放。
  normal,

  /// 网盘播放（需分发到 panHosts）。
  pan,

  /// 混合（直链 + 网盘）。
  hybrid;

  static PlayMode fromJson(String? v) => switch (v) {
        'pan' => PlayMode.pan,
        'hybrid' => PlayMode.hybrid,
        'normal' => PlayMode.normal,
        _ => PlayMode.normal,
      };
}

/// 播放源（一次可播放的媒体）。
class PlayerSource {
  const PlayerSource({
    required this.url,
    this.headers = const <String, String>{},
    this.title,
    this.isLive = false,
    this.mimeType,
    this.source = '',
    this.fallbackUrl,
    this.fallbackHeaders = const <String, String>{},
    this.fallbackSource = '',
    this.fallbackUseQuarkProxy = false,
  });

  /// 播放地址。
  final String url;

  /// 自定义请求头（对齐 `PlayerContentResult.header`）。
  final Map<String, String> headers;

  /// 显示标题。
  final String? title;

  /// 是否直播流。
  final bool isLive;

  /// MIME 类型（如 `application/vnd.apple.mpegurl`）。
  final String? mimeType;

  /// 主线路来源标记（对齐 iOS `PlayResult.source`：`download_url` /
  /// `v2-play-m3u8` / `uc_tv_token` / `v2-play` / `transcode` / `node-pan` 等）。
  ///
  /// 兜底链用于识别「原画直链」主线路（`download_url`）以决定是否启用首帧超时。
  final String source;

  /// 兜底播放地址（对齐 iOS `PlayResult.fallbackURL`；null 表示无兜底链）。
  final String? fallbackUrl;

  /// 兜底请求头（对齐 iOS `PlayResult.fallbackHeaders`）。
  final Map<String, String> fallbackHeaders;

  /// 兜底来源标记（对齐 iOS `PlayResult.fallbackSource`）。
  final String fallbackSource;

  /// 兜底线路是否需要走夸克 Go 代理（`registerQuarkStream`）。
  ///
  /// 对齐 iOS：夸克兜底线路触发时经本地代理注入鉴权头；其余网盘走直链。
  final bool fallbackUseQuarkProxy;

  /// 是否 HLS（m3u8）。
  bool get isHls =>
      url.contains('.m3u8') || (mimeType?.contains('mpegurl') ?? false);

  /// 是否具备可切换的兜底线路。
  bool get hasFallback => fallbackUrl != null && fallbackUrl!.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'url': url,
        if (headers.isNotEmpty) 'headers': headers,
        if (title != null) 'title': title,
        'isLive': isLive,
        if (mimeType != null) 'mimeType': mimeType,
        if (source.isNotEmpty) 'source': source,
        if (fallbackUrl != null) 'fallbackUrl': fallbackUrl,
        if (fallbackHeaders.isNotEmpty) 'fallbackHeaders': fallbackHeaders,
        if (fallbackSource.isNotEmpty) 'fallbackSource': fallbackSource,
        if (fallbackUseQuarkProxy) 'fallbackUseQuarkProxy': fallbackUseQuarkProxy,
      };

  factory PlayerSource.fromJson(Map<String, Object?> j) => PlayerSource(
        url: (j['url'] ?? '').toString(),
        headers: (j['headers'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v.toString())) ??
            const <String, String>{},
        title: j['title']?.toString(),
        isLive: j['isLive'] as bool? ?? false,
        mimeType: j['mimeType']?.toString(),
        source: (j['source'] as String?) ?? '',
        fallbackUrl: j['fallbackUrl']?.toString(),
        fallbackHeaders: (j['fallbackHeaders'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v.toString())) ??
            const <String, String>{},
        fallbackSource: (j['fallbackSource'] as String?) ?? '',
        fallbackUseQuarkProxy: j['fallbackUseQuarkProxy'] as bool? ?? false,
      );
}

/// 播放器状态。
enum PlayerState {
  idle,
  opening,
  playing,
  paused,
  buffering,
  ended,
  error,
}

/// 播放进度。
class PlaybackProgress {
  const PlaybackProgress({
    required this.positionMs,
    required this.durationMs,
    required this.bufferedMs,
    this.isLive = false,
  });

  final int positionMs;
  final int durationMs;
  final int bufferedMs;
  final bool isLive;

  /// 进度百分比（直播或时长未知时为 0）。
  double get percent {
    if (isLive || durationMs <= 0) return 0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  @override
  String toString() => 'PlaybackProgress(pos=${positionMs}ms, '
      'dur=${durationMs}ms, buf=${bufferedMs}ms, live=$isLive)';
}

/// 播放器接口（平台适配层实现）。
abstract class Player {
  /// 当前后端。
  PlayerBackend get backend;

  /// 可用后端列表（按优先级）。
  List<PlayerBackend> get availableBackends;

  /// 视频纹理输出面的 Flutter textureId。
  ///
  /// `null` 表示当前后端**无纹理输出**（Dart 侧渲染深色占位，避免「有声无画」
  /// 时误判为黑屏故障）；非 null 时由 [VideoSurface] 以 `Texture(textureId:)`
  /// 承载，对齐 iOS `PlayerContainerView` 的画面层语义（R-渲1）。
  int? get textureId;

  /// 状态流式回调。
  set onStateChanged(void Function(PlayerState)? handler);

  /// 进度流式回调。
  set onProgress(void Function(PlaybackProgress)? handler);

  /// 视频尺寸回调（R-渲1：输出面按纵横比自适应，对齐 iOS `videoGravity`）。
  ///
  /// 原生解出视频轨后上报（宽/高像素）；不上报时播放页按拉伸铺满处理。
  set onVideoSize(void Function(int width, int height)? handler);

  /// 错误回调。
  set onError(void Function(String message, {bool fatal})? handler);

  /// 打开媒体源。
  Future<void> open(PlayerSource source);

  /// 播放。
  Future<void> play();

  /// 暂停。
  Future<void> pause();

  /// 跳转到指定位置（毫秒）。
  Future<void> seekTo(int positionMs);

  /// 设置音量（0.0 ~ 1.0）。
  Future<void> setVolume(double volume);

  /// 设置倍速。
  Future<void> setSpeed(double speed);

  /// 释放资源。
  Future<void> dispose();
}

/// 后端选择器（D6 策略：主后端失败时回退）。
class PlayerBackendSelector {
  PlayerBackendSelector._();

  /// 按平台返回后端降级链。
  ///
  /// - Android：Media3 → MDK → libVLC
  /// - Windows/macOS：libmpv → MDK
  /// - iOS：nativeiOS（不迁移）
  ///
  /// 链首为**默认主后端**（默认路径不经过 MDK，保持既有行为）；复杂封装 /
  /// 直播 FLV 等需全格式时由 [PlayerBackendSelector] / `PlayerController` 改投
  /// **MDK 优先**（统一内核），失败再依次回退。
  static List<PlayerBackend> chainFor(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return const <PlayerBackend>[
          PlayerBackend.media3,
          PlayerBackend.mdk,
          PlayerBackend.libVLC,
        ];
      case 'windows':
      case 'macos':
        return const <PlayerBackend>[
          PlayerBackend.libmpv,
          PlayerBackend.mdk,
        ];
      case 'ios':
        return const <PlayerBackend>[PlayerBackend.nativeiOS];
      default:
        return const <PlayerBackend>[PlayerBackend.media3];
    }
  }

  /// 挑选初始后端（M1）。
  ///
  /// 默认返回**链首**（各端主后端，默认路径不经过 MDK）；当 [needsFullFormat]
  /// 为真（复杂封装 / 直播 FLV）时按统一内核口径优先：**MDK → libVLC → libmpv**，
  /// 三者皆不在链中则回链首。
  ///
  /// 纯函数（无平台分支），便于逐端单测。
  static PlayerBackend initialBackend({
    required List<PlayerBackend> chain,
    required bool needsFullFormat,
  }) {
    if (needsFullFormat) {
      if (chain.contains(PlayerBackend.mdk)) return PlayerBackend.mdk;
      if (chain.contains(PlayerBackend.libVLC)) return PlayerBackend.libVLC;
      if (chain.contains(PlayerBackend.libmpv)) return PlayerBackend.libmpv;
    }
    return chain.first;
  }

  /// 判断某 URL 是否需要回退到全格式播放器（libVLC）。
  ///
  /// 契约（计划书 1092 行）：MKV 等复杂封装 → libVLC 回退。
  static bool needsFallback(String url) {
    final String u = url.toLowerCase();
    const List<String> complexContainers = <String>[
      '.mkv', '.flv', '.ts', '.rmvb', '.avi', '.wmv', '.m2ts',
    ];
    for (final String ext in complexContainers) {
      if (u.contains(ext)) return true;
    }
    return false;
  }
}
