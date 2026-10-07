/// 平台层：弹幕数据源（批次 C · C-03 接线）。
///
/// 对齐 iOS `LogVarDanmakuService`（`vbox/Services/LogVarDanmakuService.swift`）：
/// 文件名 → 匹配 episodeId → 拉取弹幕列表 → 解析为 [DanmakuItem]；另含发送。
///
/// 接口（默认源 `https://uzdm.616222.xyz`，可用自定义源覆盖）：
///  - `POST /api/v2/match`            `{fileName}` → `{success, matches:[{episodeId}]}`
///  - `GET  /api/v2/comment/{id}`     → `{comments:[{cid,p|progress|time,m|content,type,color}]}`
///  - `GET  /api/v2/search/anime?keyword=` → `{animes:[{animeId,...}]}`
///  - `GET  /api/v2/bangumi/{animeId}` → `{bangumi:{episodes:[{episodeId,episodeNumber}]}}`
///  - `POST /api/v2/comment/{id}`     `{time,mode,color,comment}` → 发送
///
/// 网络失败一律降级为空列表 / false（不抛异常），保证播放不被弹幕阻断。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'danmaku_item.dart';
import 'danmaku_parser.dart';

/// 弹幕数据源（可注入 [client] / [baseUrl] 便于测试）。
class DanmakuService {
  /// 构造。
  DanmakuService({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 10),
  })  : _client = client,
        baseUrl = _normalizeBase(baseUrl);

  /// 默认弹幕源（对齐 iOS `defaultBaseURL`）。
  static const String defaultBaseUrl = 'https://uzdm.616222.xyz';

  final http.Client? _client;

  /// 生效的弹幕源地址（去除末尾斜杠）。
  final String baseUrl;

  /// 单请求超时。
  final Duration timeout;

  http.Client get _http => _client ?? (_default ??= http.Client());
  http.Client? _default;

  /// 释放内部自建 client（注入者由调用方自行释放）。
  void close() {
    _default?.close();
    _default = null;
  }

  static String _normalizeBase(String? url) {
    final String t = (url ?? '').trim();
    if (t.isEmpty) return defaultBaseUrl;
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  // ─────────────── 拉取 ───────────────

  /// 按文件名匹配 episodeId（对齐 iOS `matchEpisode`）；失败 → null。
  Future<int?> matchEpisode(String fileName) async {
    final String key = _normalizeFileName(fileName);
    if (key.isEmpty) return null;
    try {
      final http.Response resp = await _http
          .post(
            Uri.parse('$baseUrl/api/v2/match'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{'fileName': key}),
          )
          .timeout(timeout);
      if (resp.statusCode != 200) return null;
      return parseMatchedEpisodeId(resp.body);
    } catch (_) {
      return null;
    }
  }

  /// 按 episodeId 拉取弹幕（对齐 iOS `fetchDanmaku(episodeId:)`）。
  Future<List<DanmakuItem>> fetchByEpisodeId(int episodeId) async {
    try {
      final http.Response resp = await _http
          .get(Uri.parse('$baseUrl/api/v2/comment/$episodeId'))
          .timeout(timeout);
      if (resp.statusCode != 200) return const <DanmakuItem>[];
      return parseComments(resp.body);
    } catch (_) {
      return const <DanmakuItem>[];
    }
  }

  /// 按番剧 id + 集数拉取（对齐 iOS `fetchDanmaku(animeId:episode:)`）。
  Future<List<DanmakuItem>> fetchByAnime(int animeId, int episode) async {
    try {
      final http.Response resp = await _http
          .get(Uri.parse('$baseUrl/api/v2/bangumi/$animeId'))
          .timeout(timeout);
      if (resp.statusCode != 200) return const <DanmakuItem>[];
      final int? episodeId = parseEpisodeIdByNumber(resp.body, episode);
      if (episodeId == null) return const <DanmakuItem>[];
      return await fetchByEpisodeId(episodeId);
    } catch (_) {
      return const <DanmakuItem>[];
    }
  }

  /// 按剧名搜索 animeId（对齐 iOS `searchAnime`）。
  Future<int?> searchAnime(String keyword) async {
    final String key = keyword.trim();
    if (key.isEmpty) return null;
    try {
      final http.Response resp = await _http
          .get(Uri.parse(
              '$baseUrl/api/v2/search/anime?keyword=${Uri.encodeQueryComponent(key)}'))
          .timeout(timeout);
      if (resp.statusCode != 200) return null;
      return parseAnimeId(resp.body);
    } catch (_) {
      return null;
    }
  }

  /// 匹配并拉取（对齐 iOS `matchAndFetch`）：match 命中优先，否则回退剧名搜索。
  Future<DanmakuFetchResult> matchAndFetch(String query) async {
    final int? episodeId = await matchEpisode(query);
    if (episodeId != null) {
      final List<DanmakuItem> items = await fetchByEpisodeId(episodeId);
      if (items.isNotEmpty) {
        return DanmakuFetchResult(items: items, episodeId: episodeId);
      }
    }
    final String name = _extractTitle(query);
    if (name.isEmpty) return const DanmakuFetchResult(items: <DanmakuItem>[]);
    final int? animeId = await searchAnime(name);
    if (animeId == null) return const DanmakuFetchResult(items: <DanmakuItem>[]);
    final int episode = _extractEpisodeNumber(query);
    final List<DanmakuItem> items = await fetchByAnime(animeId, episode);
    return DanmakuFetchResult(items: items, episodeId: episodeId);
  }

  /// 发送弹幕（对齐 iOS `sendDanmaku`）；成功 → true。
  Future<bool> send({
    required int episodeId,
    required String content,
    required double timeSec,
    int mode = 1,
    int color = 0xFFFFFF,
  }) async {
    final String text = content.trim();
    if (text.isEmpty || timeSec < 0) return false;
    try {
      final http.Response resp = await _http
          .post(
            Uri.parse('$baseUrl/api/v2/comment/$episodeId'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'time': timeSec,
              'mode': mode,
              'color': color,
              'comment': text,
            }),
          )
          .timeout(timeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─────────────── 纯解析（可单测） ───────────────

  /// 解析 `POST /api/v2/match` 响应 → episodeId。
  static int? parseMatchedEpisodeId(String body) {
    final Object? root = _decode(body);
    if (root is Map) {
      if (root['success'] == false) return null;
      final Object? matches = root['matches'];
      if (matches is List && matches.isNotEmpty) {
        final Object? first = matches.first;
        if (first is Map) return _asInt(first['episodeId']);
      }
    }
    return null;
  }

  /// 解析 `GET /api/v2/search/anime` 响应 → animeId。
  static int? parseAnimeId(String body) {
    final Object? root = _decode(body);
    if (root is Map) {
      final Object? animes = root['animes'];
      if (animes is List && animes.isNotEmpty) {
        final Object? first = animes.first;
        if (first is Map) {
          return _asInt(first['animeId']) ?? _asInt(first['anime_id']);
        }
      }
    } else if (root is List && root.isNotEmpty) {
      final Object? first = root.first;
      if (first is Map) {
        return _asInt(first['animeId']) ?? _asInt(first['anime_id']);
      }
    }
    return null;
  }

  /// 解析 `GET /api/v2/bangumi/{id}` 响应，取指定集数的 episodeId（缺省取首集）。
  static int? parseEpisodeIdByNumber(String body, int episode) {
    final Object? root = _decode(body);
    if (root is! Map) return null;
    final Object? bangumi = root['bangumi'];
    if (bangumi is! Map) return null;
    final Object? episodes = bangumi['episodes'];
    if (episodes is! List || episodes.isEmpty) return null;
    Map<Object?, Object?>? fallback;
    for (final Object? raw in episodes) {
      if (raw is! Map) continue;
      fallback ??= raw;
      final int num =
          _asInt(raw['episodeNumber']) ?? _asInt(raw['episode_number']) ?? -1;
      if (num == episode) return _asInt(raw['episodeId']);
    }
    return fallback == null ? null : _asInt(fallback['episodeId']);
  }

  /// 解析 `GET /api/v2/comment/{id}` 响应 → 弹幕列表。
  ///
  /// 兼容三种形态：`{comments:[...]}`（弹弹play / logvar）、JSON 数组、
  /// Bilibili XML（回落 [DanmakuParser]）。
  static List<DanmakuItem> parseComments(String body) {
    final String trimmed = body.trim();
    if (trimmed.isEmpty) return const <DanmakuItem>[];
    final Object? root = _decode(trimmed);
    if (root is Map && root['comments'] is List) {
      final List<DanmakuItem> out = <DanmakuItem>[];
      int i = 0;
      for (final Object? raw in root['comments'] as List) {
        if (raw is! Map) continue;
        final DanmakuItem? item = _fromComment(raw, i);
        if (item != null) {
          out.add(item);
          i++;
        }
      }
      return out;
    }
    // 非 `comments` 结构 → 交回通用解析器（JSON 数组 / Bilibili XML）。
    return DanmakuParser.parse(trimmed);
  }

  static DanmakuItem? _fromComment(Map<Object?, Object?> c, int index) {
    final String content =
        (c['m'] ?? c['content'] ?? c['text'] ?? '').toString().trim();
    if (content.isEmpty) return null;

    int mode = 1;
    int color = 0xFFFFFF;
    double sizePx = 16;
    double? timeSec;

    final Object? p = c['p'];
    if (p is String && p.isNotEmpty) {
      final List<String> parts = p.split(',');
      timeSec = double.tryParse(parts.isNotEmpty ? parts[0] : '');
      if (parts.length > 1) mode = int.tryParse(parts[1]) ?? 1;
      if (parts.length > 2) sizePx = _mapSizeLevel(int.tryParse(parts[2]) ?? 25);
      if (parts.length > 3) color = int.tryParse(parts[3]) ?? 0xFFFFFF;
    }
    if (timeSec == null) {
      final num? t = _asNum(c['progress']) ?? _asNum(c['time']);
      // 弹弹play 的 progress 为毫秒，time 为秒；> 1000 视为毫秒。
      if (t != null) timeSec = t > 1000 ? t / 1000.0 : t.toDouble();
    }
    if (timeSec == null) return null;

    final Object? type = c['type'] ?? c['mode'];
    if (type != null) mode = _asInt(type) ?? mode;

    return DanmakuItem(
      content: content,
      timeMs: (timeSec * 1000).round(),
      mode: DanmakuMode.fromInt(mode),
      color: 0xFF000000 | (color & 0xFFFFFF),
      sizePx: sizePx,
      id: (c['cid'] ?? c['id'] ?? 'c$index').toString(),
    );
  }

  // ─────────────── 内部工具 ───────────────

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static int? _asInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static num? _asNum(Object? v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  /// Bilibili 25 档字号 → px（与 [DanmakuParser] 映射保持一致）。
  static double _mapSizeLevel(int level) {
    if (level <= 0) return 16;
    if (level >= 25) return 16 + (level - 25) * 0.5;
    return 12 + level * 0.16;
  }

  /// 归一化文件名（对齐 iOS `normalizeFileName`：去扩展名 / 括号 / 多余空白）。
  static String _normalizeFileName(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    String name = dot > 0 ? fileName.substring(0, dot) : fileName;
    name = name
        .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|【[^】]*】'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return name;
  }

  /// 提取剧名（对齐 iOS `extractAnimeName`）。
  static String _extractTitle(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    String name = dot > 0 ? fileName.substring(0, dot) : fileName;
    name = name
        .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|【[^】]*】'), '')
        .replaceAll(RegExp(r'[\s._\-]+(?:[Ss]\d{1,2})?(?:[Ee][Pp]?\d{1,3})?$'), '')
        .replaceAll(RegExp(r'第\s*\d{1,3}\s*[集话期].*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return name;
  }

  /// 提取集数（对齐 iOS `extractEpisodeNumber`；缺省 1）。
  static int _extractEpisodeNumber(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    final String name = dot > 0 ? fileName.substring(0, dot) : fileName;
    const List<String> patterns = <String>[
      r'[Ee][Pp]?(\d{1,3})(?:[^0-9]|$)',
      r'第\s*(\d{1,3})\s*[集话期]',
      r'\.\s*(\d{1,3})\s*\.',
    ];
    for (final String pattern in patterns) {
      final RegExpMatch? m = RegExp(pattern).firstMatch(name);
      if (m == null) continue;
      final int? num = int.tryParse(m.group(1) ?? '');
      if (num != null && num > 0) return num;
    }
    return 1;
  }
}

/// 弹幕拉取结果（列表 + 命中的 episodeId，供发送复用）。
class DanmakuFetchResult {
  /// 构造。
  const DanmakuFetchResult({
    required this.items,
    this.episodeId,
  });

  /// 弹幕列表（可能为空）。
  final List<DanmakuItem> items;

  /// 命中的 episodeId（未命中 / 回退搜索命中时为 null）。
  final int? episodeId;

  /// 是否为空结果。
  bool get isEmpty => items.isEmpty;
}