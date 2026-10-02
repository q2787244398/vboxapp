/// 平台层：播放路由（批次 C · C-01 路由 → 后端选择）。
///
/// 三端差异化后端选择的判定依据：按播放源特征解析出路由类型，
/// 再由 [PlaybackRouteResolver] 决定各平台的初始后端与降级链。
library;

import '../../domain/entities/player/player.dart';

/// 播放路由类型。
enum PlaybackRoute {
  /// 影视剧集（点播直链 / HLS）。
  detail,

  /// 直播（HLS / FLV 直播流）。
  live,

  /// 网盘播放（直链 / 转存分发）。
  pan,

  /// 音频（音乐 / 播客）。
  music,

  /// 本地文件（file:// 或绝对路径）。
  local,
}

/// 播放路由判定（C-01）。
///
/// 规则（对齐 iOS `PlayerRouteResolver` 语义）：
/// - [PlayerSource.isLive] → 直播；
/// - `file://` / 绝对路径 / Windows 盘符路径 → 本地；
/// - 音频扩展名 → 音乐；
/// - 其余（含网盘直链，网盘模式由调用方经 `mimeType` 或显式 route 标记）→ 影视。
class PlaybackRouteResolver {
  PlaybackRouteResolver._();

  /// 音频扩展名清单。
  static const List<String> audioExtensions = <String>[
    '.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.oga', '.opus', '.wma',
  ];

  /// 由播放源解析路由。
  static PlaybackRoute resolve(PlayerSource source) {
    if (source.isLive) return PlaybackRoute.live;
    final String u = source.url.trim().toLowerCase();
    if (_looksLocal(u)) return PlaybackRoute.local;
    if (u.endsWith('.flv')) return PlaybackRoute.live;
    for (final String ext in audioExtensions) {
      if (u.endsWith(ext)) return PlaybackRoute.music;
    }
    return PlaybackRoute.detail;
  }

  /// 是否本地路径（file:// 前缀 / 绝对路径 / Windows 盘符）。
  static bool _looksLocal(String url) {
    if (url.startsWith('file://')) return true;
    if (url.startsWith('/')) return true;
    return RegExp(r'^[a-z]:[\\/]').hasMatch(url);
  }
}
