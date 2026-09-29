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

  /// iOS 原生（不迁移，仅作契约对齐占位）。
  nativeiOS,
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

  /// 是否 HLS（m3u8）。
  bool get isHls =>
      url.contains('.m3u8') || (mimeType?.contains('mpegurl') ?? false);

  Map<String, Object?> toJson() => <String, Object?>{
        'url': url,
        if (headers.isNotEmpty) 'headers': headers,
        if (title != null) 'title': title,
        'isLive': isLive,
        if (mimeType != null) 'mimeType': mimeType,
      };

  factory PlayerSource.fromJson(Map<String, Object?> j) => PlayerSource(
        url: (j['url'] ?? '').toString(),
        headers: (j['headers'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v.toString())) ??
            const <String, String>{},
        title: j['title']?.toString(),
        isLive: j['isLive'] as bool? ?? false,
        mimeType: j['mimeType']?.toString(),
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

  /// 状态流式回调。
  set onStateChanged(void Function(PlayerState)? handler);

  /// 进度流式回调。
  set onProgress(void Function(PlaybackProgress)? handler);

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
  /// - Android：Media3 → libVLC
  /// - Windows/macOS：libmpv
  /// - iOS：nativeiOS（不迁移）
  static List<PlayerBackend> chainFor(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return const <PlayerBackend>[
          PlayerBackend.media3,
          PlayerBackend.libVLC,
        ];
      case 'windows':
      case 'macos':
        return const <PlayerBackend>[PlayerBackend.libmpv];
      case 'ios':
        return const <PlayerBackend>[PlayerBackend.nativeiOS];
      default:
        return const <PlayerBackend>[PlayerBackend.media3];
    }
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
