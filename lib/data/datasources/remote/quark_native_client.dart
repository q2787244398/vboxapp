/// 数据层：夸克网盘原生分享链客户端（批次 F · F-P01，对齐 iOS
/// `CloudDriveManager` 的夸克分支）。
///
/// 唯一真相源：`vbox/Services/CloudDriveManager.swift`
///   · `quarkExtractShareInfo`（L2589）：分享链接 → `pwdId` / `passcode`；
///   · `quarkAPIURL` / `quarkAPIURLWithStrictQuery`（L2616/L2646）：`drive-pc.quark.cn`
///     统一 query（`pr=ucpro&fr=pc&uc_param_str=`）+ stoken 严格编码；
///   · `quarkSetCommonHeaders`（L2626）：Cookie / Origin / Referer / UA / X-Client；
///   · `quarkGetShareToken`（L2755）：`POST /1/clouddrive/share/sharepage/token`；
///   · `quarkGetShareDetail`（L3795）：`GET …/sharepage/detail`（`_size=100` 分页）；
///   · `quarkCollectAllPlayableFiles`（L3772）：递归收集可播放文件（≤20 页）；
///   · `quarkSaveShare`（L3845）：`POST …/sharepage/save`（转存到根 `to_pdir_fid=0`）；
///   · `quarkPollTask`（L3618）：`GET /1/clouddrive/task` 轮询转存落盘；
///   · `quarkRefreshVideoAuth`（L4211）：`POST /1/clouddrive/file/v2/play` →
///     `video_list` 按 `low→4k` 选流。
///
/// 简化登记（如实）：
///   · **Set-Cookie 合并**：由 HTTP 桥 `SpiderHttpBridge` 的 **cookie jar**
///     （`storeFromResponse` + 每请求自动附加）等价覆盖，无需客户端显式合并；
///   · **转存 fid 缓存**：已实现（契约键 `quark_saved_fid_cache_v1`，TTL 5 分钟、
///     上限 300，键 `pwdId|sourceFid|folderId|cookieHash`）；
///   · **空间清理**（`quarkCleanShareOriginIfNeeded`，容量阈值触发删除
///     「来自：分享」旧转存 + 根目录视频）——**NC-清1 已移植**：含
///     `getQuotaInfo`（member → quota/info 双端点）、`file/sort` 收集、
///     `file/delete` 分批删除（含转存缓存受保护 fid 排除）；另移植
///     `deleteFiles`（对齐 iOS `quarkDeleteFiles`：删除 + 回收站彻底清理）。
///     差异登记：iOS 返回合并后 Cookie，Flutter 由 HTTP 桥 cookie jar 等价
///     承载，故本层改为返回清理条数（便于日志/测试断言）。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;

import '../../../domain/entities/cloud/cloud_drive.dart';
import '../../../platform/spider/spider_http_bridge.dart';
import '../local/prefs_manager.dart';
import 'cloud_drive_cleanup_scheduler.dart';

/// 夸克分享文件条目（对齐 iOS `QuarkShareFile`）。
class QuarkShareFile {
  /// 构造。
  const QuarkShareFile({
    required this.fid,
    required this.fileName,
    this.shareFidToken = '',
    this.pdirFid = '',
    this.isDir = false,
  });

  /// 文件 / 文件夹 ID。
  final String fid;

  /// 文件名。
  final String fileName;

  /// 分享侧 fid token（转存需带上）。
  final String shareFidToken;

  /// 所属目录 fid。
  final String pdirFid;

  /// 是否文件夹。
  final bool isDir;
}

/// 夸克取链结果。
class QuarkPlayResult {
  /// 构造。
  const QuarkPlayResult({required this.url, required this.fileName});

  /// 播放地址。
  final String url;

  /// 关联文件名（缓存键 / 展示用）。
  final String fileName;
}

/// 夸克原生链异常（对齐 iOS `DriveError` 分档文案）。
class QuarkNativeException implements Exception {
  /// 构造。
  const QuarkNativeException(this.message);

  /// 文案。
  final String message;

  @override
  String toString() => 'QuarkNativeException($message)';
}

/// 夸克原生分享链客户端。
class QuarkNativeClient {
  /// 构造（[bridge] 供测试注入假传输；[prefs] 供测试注入偏好存储）。
  QuarkNativeClient({SpiderHttpBridge? bridge, PrefsManager? prefs})
      : _bridge = bridge ?? SpiderHttpBridge(),
        _prefs = prefs;

  /// 转存 fid 缓存契约键（对齐 iOS `quark_saved_fid_cache_v1`）。
  static const String savedFidCacheKey = 'quark_saved_fid_cache_v1';

  /// 转存 fid 缓存有效期（对齐 iOS `ttl: 5 * 60`）。
  static const Duration savedFidTtl = Duration(minutes: 5);

  /// 转存 fid 缓存上限（对齐 iOS `> 300` 裁剪）。
  static const int savedFidCacheMax = 300;

  /// API 主机（对齐 iOS `quarkAPIURL`）。
  static const String apiHost = 'https://drive-pc.quark.cn';

  /// 默认 Referer（非分享场景）。
  static const String defaultReferer = 'https://pan.quark.cn/';

  /// 播放清晰度优先级（对齐 iOS：普通会员下 low 最流畅）。
  static const List<String> qualityOrder = <String>[
    'low', 'normal', 'high', 'super', '2k', '4k',
  ];

  /// 可播放扩展名（对齐 iOS `quarkIsPlayableFileName`）。
  static const List<String> playableExts = <String>[
    'mp4', 'mkv', 'mov', 'm3u8', 'avi', 'wmv', 'flv', 'ts', 'mp3', 'm4a',
  ];

  final SpiderHttpBridge _bridge;
  final PrefsManager? _prefs;

  /// 转存后延迟清理调度（对齐 iOS `scheduleCleanup`；缺省不调度）。
  CloudDriveCleanupScheduler? cleanupScheduler;

  // ─────────────── 转存 fid 缓存（契约键 `quark_saved_fid_cache_v1`）───────────────

  Map<String, Object?>? _cacheMemory;
  bool _cacheLoaded = false;

  /// Cookie 摘要（对齐 iOS `String(cookie.hash)`：仅作缓存键区分，不含明文）。
  static String cookieHash(String cookie) =>
      crypto.sha256.convert(utf8.encode(cookie)).toString().substring(0, 16);

  /// 缓存键 `pwdId|sourceFid|folderId|cookieHash`（对齐 iOS `quarkSavedFidCacheKey`）。
  static String cacheKeyFor({
    required String pwdId,
    required String sourceFid,
    required String folderId,
    required String cookie,
  }) =>
      '$pwdId|$sourceFid|$folderId|${cookieHash(cookie)}';

  Future<Map<String, Object?>> _loadCache() async {
    if (_cacheLoaded && _cacheMemory != null) return _cacheMemory!;
    _cacheLoaded = true;
    Map<String, Object?> cache = <String, Object?>{};
    try {
      final PrefsManager p = _prefs ?? PrefsManager.instance;
      final String raw = await p.getString(savedFidCacheKey);
      if (raw.isNotEmpty) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) cache = decoded.cast<String, Object?>();
      }
    } catch (_) {
      // 存储不可用 → 退化为内存缓存。
    }
    _cacheMemory = cache;
    return cache;
  }

  Future<void> _saveCache(Map<String, Object?> cache) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<MapEntry<String, Object?>> alive = cache.entries
        .where((MapEntry<String, Object?> e) {
          final Map<String, Object?>? v =
              e.value is Map ? (e.value as Map).cast<String, Object?>() : null;
          final int exp = (v?['expiresAt'] as num?)?.toInt() ?? 0;
          return exp > now;
        })
        .toList()
      ..sort((MapEntry<String, Object?> a, MapEntry<String, Object?> b) {
        final int ta = ((a.value as Map)['createdAt'] as num?)?.toInt() ?? 0;
        final int tb = ((b.value as Map)['createdAt'] as num?)?.toInt() ?? 0;
        return tb.compareTo(ta);
      });
    final Map<String, Object?> capped = <String, Object?>{
      for (final MapEntry<String, Object?> e in alive.take(savedFidCacheMax))
        e.key: e.value,
    };
    _cacheMemory = capped;
    try {
      final PrefsManager p = _prefs ?? PrefsManager.instance;
      await p.set(savedFidCacheKey, jsonEncode(capped));
    } catch (_) {
      // 落盘失败不阻断播放（下次重存）。
    }
  }

  /// 命中未过期的转存 fid（对齐 iOS `quarkCachedSavedTopFids`）。
  Future<List<String>?> cachedSavedFids(String key) async {
    final Map<String, Object?> cache = await _loadCache();
    final Object? raw = cache[key];
    if (raw is! Map) return null;
    final Map<String, Object?> v = raw.cast<String, Object?>();
    final int exp = (v['expiresAt'] as num?)?.toInt() ?? 0;
    if (exp <= DateTime.now().millisecondsSinceEpoch) return null;
    final Object? top = v['topLevelFids'];
    if (top is! List) return null;
    final List<String> ids =
        top.map((Object? e) => '$e').toList(growable: false);
    return ids.isEmpty ? null : ids;
  }

  /// 存入转存 fid（对齐 iOS `quarkStoreSavedItem`：空 / 全 `"0"` 不入缓存）。
  Future<void> storeSavedFids(
    String key,
    List<String> topLevelFids, {
    Duration? ttl,
  }) async {
    if (topLevelFids.isEmpty ||
        topLevelFids.every((String id) => id == '0')) {
      return;
    }
    final Map<String, Object?> cache =
        Map<String, Object?>.of(await _loadCache());
    final int now = DateTime.now().millisecondsSinceEpoch;
    cache[key] = <String, Object?>{
      'topLevelFids': topLevelFids,
      'createdAt': now,
      'expiresAt': now + (ttl ?? savedFidTtl).inMilliseconds,
    };
    await _saveCache(cache);
  }

  /// 清理历史转存对象（对齐 iOS `quarkCleanupPreviousSavedItems`）。
  ///
  /// 新转存完成后，删除缓存中**除 [excludingKey]** 外的全部历史转存 fid 并移除
  /// 对应缓存键（避免历史转存文件长期占用网盘空间）。返回提交删除的文件数。
  Future<int> cleanupPreviousSavedItems({
    required String excludingKey,
    required String cookie,
  }) async {
    final Map<String, Object?> cache = await _loadCache();
    final List<String> keysToRemove = <String>[];
    final List<String> fidsToDelete = <String>[];
    for (final MapEntry<String, Object?> entry in cache.entries) {
      if (entry.key == excludingKey) continue;
      keysToRemove.add(entry.key);
      final Object? v = entry.value;
      if (v is Map) {
        final Object? top = v['topLevelFids'];
        if (top is List) {
          fidsToDelete.addAll(top.map((Object? e) => '$e'));
        }
      }
    }
    final List<String> uniqueFids = fidsToDelete
        .where((String id) => id.isNotEmpty && id != '0')
        .toSet()
        .toList(growable: false);
    if (uniqueFids.isEmpty) return 0;

    final int deleted = await deleteFiles(fileIds: uniqueFids, cookie: cookie);
    for (final String key in keysToRemove) {
      cache.remove(key);
    }
    await _saveCache(cache);
    return deleted;
  }

  // ─────────────── 分享信息 ───────────────

  /// 解析分享链接 → `(pwdId, passcode)`（对齐 iOS `quarkExtractShareInfo`）。
  static ({String pwdId, String passcode}) extractShareInfo(String shareUrl) {
    final Uri? uri = Uri.tryParse(shareUrl);
    if (uri != null) {
      final List<String> comps =
          uri.path.split('/').where((String s) => s.isNotEmpty).toList();
      String pwdId = '';
      final int sIndex = comps.indexOf('s');
      if (sIndex >= 0 && comps.length > sIndex + 1) {
        pwdId = comps[sIndex + 1];
      } else if (comps.isNotEmpty) {
        pwdId = comps.last;
      }
      String passcode = '';
      for (final String key in <String>['pwd', 'passcode', 'password']) {
        final String? v = uri.queryParameters[key];
        if (v != null && v.isNotEmpty) {
          passcode = v;
          break;
        }
      }
      return (pwdId: pwdId, passcode: passcode);
    }
    // 退化路径（非标准 URL）：`.*/s/` 截取 + `pwd=` 提取。
    String cleaned = shareUrl.replaceAll(RegExp(r'.*/s/'), '');
    cleaned = cleaned.split('?').first;
    final RegExpMatch? m =
        RegExp(r'(pwd|passcode|password)=([^&]+)').firstMatch(shareUrl);
    return (pwdId: cleaned.trim(), passcode: m?.group(2) ?? '');
  }

  /// 分享 Referer（对齐 iOS `quarkShareReferer`）。
  static String shareReferer(String pwdId) =>
      pwdId.isEmpty ? defaultReferer : 'https://pan.quark.cn/s/$pwdId';

  /// 是否为可播放文件（对齐 iOS `quarkIsPlayableFileName`）。
  static bool isPlayableFileName(String name) {
    final String lower = name.toLowerCase();
    return playableExts.any((String e) => lower.endsWith('.$e'));
  }

  /// 统一 API URL（对齐 iOS `quarkAPIURL`）。
  static Uri apiUrl(String path, {List<(String, String)> extra = const []}) {
    return Uri.parse('$apiHost$path').replace(queryParameters: <String, String>{
      'pr': 'ucpro',
      'fr': 'pc',
      'uc_param_str': '',
      for (final (String, String) e in extra) e.$1: e.$2,
    });
  }

  /// stoken 严格查询编码（对齐 iOS `quarkStrictQueryEncode`：
  /// 仅 `A-Za-z0-9-._~` 不编码，`+` → `%2B`）。
  static String strictQueryEncode(String value) {
    const String unreserved =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final StringBuffer out = StringBuffer();
    for (final int rune in value.runes) {
      final String ch = String.fromCharCode(rune);
      out.write(unreserved.contains(ch) ? ch : Uri.encodeComponent(ch));
    }
    return out.toString();
  }

  Map<String, String> _commonHeaders(String cookie, {String? referer}) =>
      <String, String>{
        'Content-Type': 'application/json',
        if (cookie.isNotEmpty) 'Cookie': cookie,
        'Origin': 'https://pan.quark.cn',
        'Referer': referer ?? defaultReferer,
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) quark-cloud-drive/2.5.20 '
                'Chrome/100.0.4896.160 Electron/18.3.5.4-b478491100 '
                'Safari/537.36 Channel/pckk_other_ch',
        'X-Client': 'QingmanLslandApp/1.0',
      };

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  // ─────────────── 分享 token ───────────────

  /// 获取分享 `stoken`（对齐 iOS `quarkGetShareToken`）。
  Future<String> getShareToken({
    required String pwdId,
    required String passcode,
    required String cookie,
  }) async {
    final Uri url = apiUrl(
      '/1/clouddrive/share/sharepage/token',
      extra: <(String, String)>[('__t', '${_nowMs()}')],
    );
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(
        method: 'POST',
        headers: _commonHeaders(cookie, referer: shareReferer(pwdId)),
        data: jsonEncode(<String, Object?>{
          'pwd_id': pwdId,
          'passcode': passcode,
        }),
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    if (!res.ok || json == null) {
      throw const QuarkNativeException('夸克分享 token 获取失败：网络或响应异常');
    }
    final int code = _asInt(json['code']) ?? 0;
    if (code != 0) {
      throw QuarkNativeException(
        '夸克分享 token 获取失败：${json['message'] ?? 'code=$code'}',
      );
    }
    final Map<String, Object?>? data = _asMap(json['data']);
    final String st = _asString(data?['stoken']) ?? '';
    if (st.isEmpty) {
      throw const QuarkNativeException('夸克未返回 stoken');
    }
    return st;
  }

  // ─────────────── 文件列表 ───────────────

  /// 单页分享文件列表（对齐 iOS `quarkGetShareDetail`）。
  Future<List<QuarkShareFile>> getShareDetail({
    required String pwdId,
    required String stoken,
    required String pdirFid,
    required String cookie,
    int page = 1,
  }) async {
    final Uri url = apiUrl(
      '/1/clouddrive/share/sharepage/detail',
      extra: <(String, String)>[
        ('__t', '${_nowMs()}'),
        ('_fetch_banner', '1'),
        ('_fetch_total', '1'),
        ('_page', '$page'),
        ('_size', '100'),
        ('_sort', 'file_type:asc,file_name:asc'),
        ('force', '0'),
        ('pdir_fid', pdirFid),
        ('pwd_id', pwdId),
      ],
    );
    // stoken 严格编码（对齐 iOS：`+` 需编码为 %2B，否则服务端解析失败）。
    final String withStoken =
        '${url.toString()}&stoken=${strictQueryEncode(stoken)}';
    final SpiderHttpResult res = await _bridge.request(
      withStoken,
      options: SpiderHttpOptions(
        headers: _commonHeaders(cookie, referer: shareReferer(pwdId)),
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    if (json == null) {
      throw const QuarkNativeException('夸克文件列表响应异常');
    }
    final int code = _asInt(json['code']) ?? 0;
    if (code != 0) {
      throw QuarkNativeException('夸克文件列表失败：${json['message'] ?? 'code=$code'}');
    }
    final Map<String, Object?>? data = _asMap(json['data']);
    final Object? list = data?['list'];
    if (list is! List) return const <QuarkShareFile>[];
    return list
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> raw) {
          final Map<String, Object?> item = raw.cast<String, Object?>();
          final String fid = _asString(item['fid']) ?? '';
          final String name =
              _asString(item['file_name']) ?? _asString(item['name']) ?? '';
          final String token = _asString(item['share_fid_token']) ??
              _asString(item['fid_token']) ??
              '';
          final bool? dirFlag = item['dir'] as bool?;
          final bool? fileFlag = item['file'] as bool?;
          final int? fileType = _asInt(item['file_type']);
          final bool isDir = dirFlag ??
              (fileFlag == false && fileType == 0);
          return QuarkShareFile(
            fid: fid,
            fileName: name,
            shareFidToken: token,
            pdirFid: pdirFid,
            isDir: isDir,
          );
        })
        .where((QuarkShareFile f) => f.fid.isNotEmpty && f.fileName.isNotEmpty)
        .toList(growable: false);
  }

  /// 递归收集全部可播放文件（对齐 iOS `quarkCollectAllPlayableFiles`）。
  Future<List<QuarkShareFile>> collectAllPlayableFiles({
    required String pwdId,
    required String stoken,
    required String cookie,
    String pdirFid = '0',
    int maxPages = 20,
  }) async {
    final List<QuarkShareFile> out = <QuarkShareFile>[];
    await _collect(
      pwdId: pwdId,
      stoken: stoken,
      pdirFid: pdirFid,
      cookie: cookie,
      out: out,
      maxPages: maxPages,
    );
    return out;
  }

  Future<void> _collect({
    required String pwdId,
    required String stoken,
    required String pdirFid,
    required String cookie,
    required List<QuarkShareFile> out,
    required int maxPages,
  }) async {
    int page = 1;
    bool hasMore = true;
    while (hasMore) {
      final List<QuarkShareFile> files = await getShareDetail(
        pwdId: pwdId,
        stoken: stoken,
        pdirFid: pdirFid,
        cookie: cookie,
        page: page,
      );
      for (final QuarkShareFile f in files) {
        if (!f.isDir && isPlayableFileName(f.fileName)) out.add(f);
      }
      for (final QuarkShareFile dir in files.where((QuarkShareFile f) => f.isDir)) {
        await _collect(
          pwdId: pwdId,
          stoken: stoken,
          pdirFid: dir.fid,
          cookie: cookie,
          out: out,
          maxPages: maxPages,
        );
      }
      hasMore = files.length >= 100;
      page += 1;
      if (page > maxPages) break;
    }
  }

  /// 分享链接 → 全部可播放文件（对齐 iOS `quarkGetFileList`）。
  Future<List<QuarkShareFile>> getFileList({
    required String shareUrl,
    required String cookie,
  }) async {
    final ({String pwdId, String passcode}) info = extractShareInfo(shareUrl);
    if (info.pwdId.isEmpty) {
      throw const QuarkNativeException('无法识别的分享链接');
    }
    final String stoken = await getShareToken(
      pwdId: info.pwdId,
      passcode: info.passcode,
      cookie: cookie,
    );
    return collectAllPlayableFiles(
      pwdId: info.pwdId,
      stoken: stoken,
      cookie: cookie,
    );
  }

  // ─────────────── 转存 + 轮询 ───────────────

  /// 转存分享文件到根目录，返回顶层 fid 列表（对齐 iOS `quarkSaveShare`）。
  Future<List<String>> saveShare({
    required String pwdId,
    required String stoken,
    required QuarkShareFile file,
    required String cookie,
    String folderId = '0',
  }) async {
    final Uri url = apiUrl(
      '/1/clouddrive/share/sharepage/save',
      extra: <(String, String)>[('__t', '${_nowMs()}')],
    );
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(
        method: 'POST',
        headers: _commonHeaders(cookie, referer: shareReferer(pwdId)),
        data: jsonEncode(<String, Object?>{
          'fid_list': <String>[file.fid],
          'fid_token_list': <String>[file.shareFidToken],
          'to_pdir_fid': folderId,
          'pwd_id': pwdId,
          'stoken': stoken,
          'pdir_fid': file.pdirFid,
          'scene': 'link',
          'platform_original': 'chrome',
          'nu_distribute': 0,
        }),
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    if (json == null) {
      throw const QuarkNativeException('夸克转存失败：响应异常');
    }
    final int status = _asInt(json['status']) ?? 0;
    final int code = _asInt(json['code']) ?? 0;
    if (status != 200 && status != 0) {
      throw QuarkNativeException(
        '夸克转存失败：${json['message'] ?? json['msg'] ?? 'status=$status'}',
      );
    }
    if (code != 0) {
      throw QuarkNativeException(
        '夸克转存失败：${json['message'] ?? json['msg'] ?? 'code=$code'}',
      );
    }
    final Map<String, Object?>? data = _asMap(json['data']);
    final List<String> ids = _extractSavedFids(data);
    if (ids.isEmpty) {
      throw const QuarkNativeException('夸克转存后未返回文件 ID');
    }
    if (ids.every((String id) => id == '0' || id == folderId)) {
      throw const QuarkNativeException('该资源在夸克网盘中已失效（可能被和谐或转码失败）');
    }
    return ids;
  }

  List<String> _extractSavedFids(Map<String, Object?>? data) {
    if (data == null) return const <String>[];
    final Map<String, Object?>? taskResp = _asMap(data['task_resp']);
    final Map<String, Object?>? taskData = _asMap(taskResp?['data']);
    final Map<String, Object?>? saveAs = _asMap(taskData?['save_as']);
    for (final String key in <String>[
      'save_as_top_fids',
      'save_as_select_top_fids',
    ]) {
      final Object? ids = saveAs?[key];
      if (ids is List && ids.isNotEmpty) {
        return ids.map((Object? e) => '$e').toList(growable: false);
      }
    }
    final Object? fileIds = data['file_ids'];
    if (fileIds is List && fileIds.isNotEmpty) {
      return fileIds.map((Object? e) => '$e').toList(growable: false);
    }
    final Object? list = data['list'];
    if (list is List && list.isNotEmpty) {
      final List<String> ids = list
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> m) =>
              _asString(m['fid']) ?? _asString(m['file_id']) ?? '')
          .where((String s) => s.isNotEmpty)
          .toList(growable: false);
      if (ids.isNotEmpty) return ids;
    }
    return const <String>[];
  }

  /// 提取转存任务 ID（对齐 iOS `quarkLastSaveTaskId`；无则返回 null）。
  String? extractSaveTaskId(String responseBody) {
    final Map<String, Object?>? json = _decodeMap(responseBody);
    return _asString(_asMap(json?['data'])?['task_id']);
  }

  /// 轮询转存任务直到落盘（对齐 iOS `quarkPollTask`）。
  Future<void> pollTask({
    required String taskId,
    required String cookie,
    int maxRetries = 10,
    Duration interval = const Duration(seconds: 1),
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      final Uri url = apiUrl(
        '/1/clouddrive/task',
        extra: <(String, String)>[
          ('__t', '${_nowMs()}'),
          ('task_id', taskId),
          ('retry_index', '0'),
        ],
      );
      final SpiderHttpResult res = await _bridge.request(
        url.toString(),
        options: SpiderHttpOptions(headers: _commonHeaders(cookie)),
      );
      final Map<String, Object?>? json = _decodeMap(res.content);
      final Map<String, Object?>? data = _asMap(json?['data']);
      if (data != null) {
        final int status = _asInt(data['status']) ?? -1;
        final bool finish = data['finish'] as bool? ?? false;
        if (finish || status == 2) return;
        if (status == 3 || status == -1) return; // 异常：继续尝试播放
      }
      if (i < maxRetries - 1) await Future<void>.delayed(interval);
    }
  }

  // ─────────────── 取链 ───────────────

  /// 取播放地址（对齐 iOS `quarkRefreshVideoAuth`：`POST /file/v2/play`）。
  Future<String> getPlayUrl({
    required String fileId,
    required String cookie,
  }) async {
    final Uri url = apiUrl('/1/clouddrive/file/v2/play');
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(
        method: 'POST',
        headers: _commonHeaders(cookie),
        data: jsonEncode(<String, Object?>{
          'fid': fileId,
          'resolutions': 'normal,low,high,super,2k,4k',
          'supports': 'fmp4,m3u8',
        }),
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    if (json == null) {
      throw const QuarkNativeException('夸克取链响应异常');
    }
    final int code = _asInt(json['code']) ?? 0;
    if (code != 0) {
      throw QuarkNativeException('夸克 v2/play 失败：${json['message'] ?? 'code=$code'}');
    }
    final Map<String, Object?>? data = _asMap(json['data']);
    final Object? videos = data?['video_list'];
    if (videos is List) {
      // 按质量顺序 low→4k 选第一个可用流。
      for (final String quality in qualityOrder) {
        for (final Object? item in videos) {
          final Map<String, Object?>? m = _asMap(item);
          if (m == null) continue;
          final Map<String, Object?>? info = _asMap(m['video_info']);
          final String? res0 = _asString(info?['resolution']);
          final bool accessable = m['accessable'] as bool? ?? true;
          final String? u = _asString(info?['url']);
          if (res0 == quality && accessable && (u ?? '').isNotEmpty) return u!;
        }
      }
      for (final Object? item in videos) {
        final Map<String, Object?>? m = _asMap(item);
        if (m == null) continue;
        final bool accessable = m['accessable'] as bool? ?? true;
        final String? u = _asString(_asMap(m['video_info'])?['url']);
        if (accessable && (u ?? '').isNotEmpty) return u!;
      }
    }
    final String? playUrl = _asString(json['play_url']);
    if (playUrl != null && playUrl.isNotEmpty) return playUrl;
    throw const QuarkNativeException('夸克未返回可用播放地址');
  }

  /// 分享链接 → 取链（对齐 iOS `resolveQuarkPlayURL` 主链，简化清理/缓存）。
  Future<QuarkPlayResult> resolvePlayUrl({
    required String shareUrl,
    required String cookie,
    String? preferredFid,
  }) async {
    final ({String pwdId, String passcode}) info = extractShareInfo(shareUrl);
    if (info.pwdId.isEmpty) {
      throw const QuarkNativeException('无法识别的分享链接');
    }
    // 播放前检测夸克空间，快满时清理「来自：分享」目录（对齐 iOS L2309）。
    try {
      await cleanShareOriginIfNeeded(cookie: cookie, thresholdGb: 2.0);
    } catch (_) {
      // 清理失败不阻断播放（容量管理为尽力而为）。
    }
    final String stoken = await getShareToken(
      pwdId: info.pwdId,
      passcode: info.passcode,
      cookie: cookie,
    );
    final List<QuarkShareFile> files = await collectAllPlayableFiles(
      pwdId: info.pwdId,
      stoken: stoken,
      cookie: cookie,
    );
    if (files.isEmpty) {
      throw const QuarkNativeException('夸克分享内未找到可播放视频');
    }
    final QuarkShareFile source = (preferredFid != null && preferredFid.isNotEmpty)
        ? files.firstWhere(
            (QuarkShareFile f) => f.fid == preferredFid,
            orElse: () => files.first,
          )
        : files.first;
    // 转存 fid 缓存命中则跳过本次转存（对齐 iOS `quarkCachedSavedTopFids`）。
    final String cacheKey = cacheKeyFor(
      pwdId: info.pwdId,
      sourceFid: source.fid,
      folderId: '0',
      cookie: cookie,
    );
    List<String> saved = await cachedSavedFids(cacheKey) ?? const <String>[];
    if (saved.isEmpty) {
      saved = await saveShare(
        pwdId: info.pwdId,
        stoken: stoken,
        file: source,
        cookie: cookie,
      );
      await storeSavedFids(cacheKey, saved);
      // 转存成功即安排 1 小时后清理，并清理历史转存对象（对齐 iOS L2350/L2353）。
      await cleanupScheduler?.schedule(
        drive: CloudDriveType.quark,
        fileIds: saved,
        delay: const Duration(hours: 1),
      );
      await cleanupPreviousSavedItems(excludingKey: cacheKey, cookie: cookie);
    }
    final String fid = saved.first;
    final String url = await getPlayUrl(fileId: fid, cookie: cookie);
    return QuarkPlayResult(url: url, fileName: source.fileName);
  }

  // ─────────────── 空间清理（NC-清1，对齐 iOS `quarkCleanShareOriginIfNeeded` /
  //                 `quarkDeleteFiles`）───────────────

  /// 根目录清理视频后缀白名单（对齐 iOS `quarkCleanShareOriginIfNeeded` 内联表）。
  static const List<String> cleanupVideoExts = <String>[
    '.mp4', '.mkv', '.avi', '.ts', '.mov', '.flv', '.wmv', '.m4v', '.3gp',
  ];

  /// 清理目标目录名变体（对齐 iOS 四种写法）。
  static const List<String> shareOriginFolderNames = <String>[
    '来自：分享', '来自:分享', '来自分享的文件', '来自分享',
  ];

  /// 读取容量信息（对齐 iOS `quarkGetQuotaInfo`：member → quota/info 双端点）。
  ///
  /// 返回 `(used, total)` 字节；全部失败时 `total == 0`（调用方按「容量未知」
  /// 走保守清理）。Set-Cookie 合并由 HTTP 桥 cookie jar 等价承载。
  Future<({int used, int total})> getQuotaInfo({required String cookie}) async {
    final ({int used, int total})? member =
        await _quotaFromMember(cookie: cookie);
    if (member != null && member.total > 0) return member;

    final Uri url = apiUrl(
      '/1/clouddrive/quota/info',
      extra: <(String, String)>[('ut', '${_nowMs()}')],
    );
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(
        method: 'POST',
        headers: _commonHeaders(cookie),
        // iBox 抓包显示 quota/info 需要 dlt_keys，否则 405/参数错误。
        data: jsonEncode(<String, Object?>{
          'dlt_keys': <String>['uc_nor_dlt'],
        }),
      ),
    );
    if (!res.ok) return (used: 0, total: 0);
    final Map<String, Object?>? json = _decodeMap(res.content);
    if (json == null) return (used: 0, total: 0);
    final Map<String, Object?>? data = _asMap(json['data']);
    final Map<String, Object?> cap = _asMap(data?['capinfo']) ??
        _asMap(data?['capacity']) ??
        _asMap(data?['account_capacity']) ??
        data ??
        json;
    final int used =
        _asInt(cap['used'] ?? cap['size_used'] ?? data?['used']) ?? 0;
    int total =
        _asInt(cap['total'] ?? cap['size_total'] ?? data?['total']) ?? 0;
    if (total <= 0) {
      final Map<String, Object?>? account = _asMap(data?['account']);
      total = _asInt(account?['total_capacity'] ??
              account?['capacity_total'] ??
              account?['total']) ??
          0;
    }
    return (used: used, total: total);
  }

  /// member 端点容量兜底（对齐 iOS `quarkGetQuotaFromMember`）。
  Future<({int used, int total})?> _quotaFromMember(
      {required String cookie}) async {
    final Uri url = apiUrl(
      '/1/clouddrive/member',
      extra: <(String, String)>[
        ('fetch_subscribe', 'true'),
        ('fetch_identity', 'true'),
        ('_ch', 'home'),
        ('ve', '3.19.0'),
      ],
    );
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(headers: _commonHeaders(cookie)),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    final Map<String, Object?>? d = _asMap(json?['data']);
    if (d == null) return null;
    final Map<String, Object?>? cap = _asMap(d['capacity']) ??
        _asMap(d['capinfo']) ??
        _asMap(d['account_capacity']);
    int used = _asInt(cap?['used'] ?? cap?['size_used'] ?? d['used']) ?? 0;
    int total = _asInt(cap?['total'] ?? cap?['size_total'] ?? d['total']) ?? 0;
    final Map<String, Object?>? account = _asMap(d['account']);
    if (total <= 0) {
      total = _asInt(account?['total_capacity'] ??
              account?['capacity_total'] ??
              account?['total']) ??
          0;
    }
    if (used <= 0) {
      used = _asInt(account?['used_capacity'] ??
              account?['capacity_used'] ??
              account?['used']) ??
          0;
    }
    if (total > 0 && used <= 0) {
      used = total - (_asInt(d['remain']) ?? 0);
    }
    if (total <= 0) return null;
    return (used: used, total: total);
  }

  /// 容量阈值触发清理（对齐 iOS `quarkCleanShareOriginIfNeeded`）。
  ///
  /// 剩余空间低于 [thresholdGb] 时，删除「来自：分享」目录（含子文件夹）与
  /// 根目录视频；容量未知时按保守策略清理根目录最新 100 个视频。转存 fid
  /// 缓存中未过期的对象跳过，避免误删正在使用/待播放的转存文件。
  ///
  /// 返回清理条数。Set-Cookie 合并由 HTTP 桥 cookie jar 承载（差异登记）。
  Future<int> cleanShareOriginIfNeeded({
    required String cookie,
    double thresholdGb = 1.0,
  }) async {
    final ({int used, int total}) quota =
        await getQuotaInfo(cookie: cookie);
    final bool quotaAvailable = quota.total > 0;
    if (quotaAvailable) {
      final double freeGb =
          (quota.total - quota.used) / 1073741824.0;
      if (freeGb >= thresholdGb) return 0;
    }

    List<String> shareFids = const <String>[];
    for (final String name in shareOriginFolderNames) {
      final String? folderId = await _findFolderId(name, cookie);
      if (folderId != null) {
        // 分享目录内同时清理子文件夹和文件，避免文件夹形式转存残留。
        shareFids = await _collectFids(
          folderId: folderId,
          cookie: cookie,
          includeFolders: true,
        );
        break;
      }
    }
    // 容量未知时更激进：只清理根目录最新 100 个视频，避免空间爆掉。
    final List<String> rootFids = await _collectFids(
      folderId: '0',
      cookie: cookie,
      onlyVideo: true,
      limit: quotaAvailable ? null : 100,
    );

    final Set<String> all = <String>{...shareFids, ...rootFids};
    if (all.isEmpty) return 0;
    final Set<String> protected = await protectedCachedFids();
    final List<String> targets =
        all.where((String fid) => !protected.contains(fid)).toList();
    if (targets.isEmpty) return 0;
    return _deleteFidsBatched(targets, cookie: cookie);
  }

  /// 转存 fid 缓存内未过期的对象 fid（对齐 iOS `protectedCachedFileIds`）。
  Future<Set<String>> protectedCachedFids() async {
    final Map<String, Object?> cache = await _loadCache();
    final int now = _nowMs();
    final Set<String> fids = <String>{};
    for (final Object? raw in cache.values) {
      final Map<String, Object?>? v = _asMap(raw);
      if (v == null) continue;
      if ((_asInt(v['expiresAt']) ?? 0) <= now) continue;
      final Object? top = v['topLevelFids'];
      if (top is List) {
        for (final Object? e in top) {
          fids.add('$e');
        }
      }
      final String? playback = _asString(v['playbackFileId']);
      if (playback != null && playback.isNotEmpty) fids.add(playback);
    }
    return fids;
  }

  /// 删除文件并彻底清理回收站（对齐 iOS `quarkDeleteFiles`）。
  ///
  /// 返回提交删除的文件数（回收站清理为尽力而为）。
  Future<int> deleteFiles({
    required List<String> fileIds,
    required String cookie,
  }) async {
    if (fileIds.isEmpty) return 0;
    final SpiderHttpResult res = await _bridge.request(
      apiUrl('/1/clouddrive/file/delete').toString(),
      options: SpiderHttpOptions(
        method: 'POST',
        headers: _commonHeaders(cookie),
        data: jsonEncode(<String, Object?>{
          'action_type': 2,
          'filelist': fileIds,
          'exclude_fids': <String>[],
        }),
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    final String taskId = _asString(json?['task_id']) ?? '';
    if (taskId.isEmpty) return fileIds.length;

    // 彻底清理回收站：等待删除任务落盘 → recycle/list → recycle/remove。
    await Future<void>.delayed(const Duration(seconds: 1));
    final SpiderHttpResult recycleRes = await _bridge.request(
      apiUrl(
        '/1/clouddrive/file/recycle/list',
        extra: <(String, String)>[
          ('_page', '1'),
          ('_size', '100'),
          ('_sort', 'move_recycle_at:desc'),
        ],
      ).toString(),
      options: SpiderHttpOptions(headers: _commonHeaders(cookie)),
    );
    final Map<String, Object?>? recycleJson =
        _decodeMap(recycleRes.content);
    final Object? list = recycleJson?['data'];
    if (list is! List) return fileIds.length;
    final List<String> recordIds = <String>[];
    for (final Object? raw in list) {
      final Map<String, Object?>? item = _asMap(raw);
      final String recordId = _asString(item?['record_id']) ?? '';
      if (recordId.isEmpty) continue;
      if (recordId.contains(taskId) ||
          fileIds.any((String fid) => recordId.contains(fid))) {
        recordIds.add(recordId);
      }
    }
    if (recordIds.isEmpty) return fileIds.length;
    await _bridge.request(
      apiUrl('/1/clouddrive/file/recycle/remove').toString(),
      options: SpiderHttpOptions(
        method: 'POST',
        headers: _commonHeaders(cookie),
        data: jsonEncode(<String, Object?>{
          'select_mode': 2,
          'record_list': recordIds,
        }),
      ),
    );
    return fileIds.length;
  }

  /// 分批删除（对齐 iOS `deleteFids`：每批 100、批间 100ms 防风控）。
  Future<int> _deleteFidsBatched(
    List<String> fids, {
    required String cookie,
  }) async {
    const int batchSize = 100;
    int deleted = 0;
    for (int i = 0; i < fids.length; i += batchSize) {
      final List<String> batch =
          fids.sublist(i, math.min(i + batchSize, fids.length));
      final SpiderHttpResult res = await _bridge.request(
        apiUrl('/1/clouddrive/file/delete').toString(),
        options: SpiderHttpOptions(
          method: 'POST',
          headers: _commonHeaders(cookie),
          data: jsonEncode(<String, Object?>{
            'action_type': 2,
            'filelist': batch,
            'exclude_fids': <String>[],
          }),
        ),
      );
      final Map<String, Object?>? json = _decodeMap(res.content);
      if ((_asInt(json?['code']) ?? 0) == 0) deleted += batch.length;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return deleted;
  }

  /// 收集目录下文件 fid（对齐 iOS `collectFids`）。
  Future<List<String>> _collectFids({
    required String folderId,
    required String cookie,
    bool onlyVideo = false,
    int? limit,
    bool includeFolders = false,
  }) async {
    const int pageSize = 200;
    final int maxPages =
        limit != null ? math.min(10, (limit + pageSize - 1) ~/ pageSize) : 10;
    final List<String> fids = <String>[];
    for (int page = 1; page <= maxPages; page++) {
      final List<Map<String, Object?>> list = await _fileSortList(
        cookie: cookie,
        query: <(String, String)>[
          ('pdir_fid', folderId),
          ('_sort', 'file_type:asc,updated_at:desc'),
          ('_page', '$page'),
          ('_size', '$pageSize'),
          ('_fetch_total', '1'),
        ],
      );
      if (list.isEmpty) break;
      for (final Map<String, Object?> item in list) {
        final bool isDir = (_asInt(item['file_type']) == 0) ||
            (item['is_dir'] == true);
        if (isDir && !includeFolders) continue;
        if (onlyVideo && !isDir) {
          final String name = (_asString(item['file_name']) ??
                  _asString(item['name']) ??
                  '')
              .toLowerCase();
          if (!cleanupVideoExts.any((String e) => name.endsWith(e))) continue;
        }
        final String fid = _asString(item['fid']) ??
            _asString(item['file_id']) ??
            (_asInt(item['fid']) != null ? '${item['fid']}' : '');
        if (fid.isNotEmpty) fids.add(fid);
        if (limit != null && fids.length >= limit) break;
      }
      if (list.length < pageSize) break;
      if (limit != null && fids.length >= limit) break;
    }
    return fids;
  }

  /// 按名称在根目录查找文件夹 fid（对齐 iOS `findFolderId`）。
  Future<String?> _findFolderId(String name, String cookie) async {
    final List<Map<String, Object?>> list = await _fileSortList(
      cookie: cookie,
      query: <(String, String)>[
        ('pdir_fid', '0'),
        ('_sort', 'file_type:asc,file_name:asc'),
        ('_page', '1'),
        ('_size', '200'),
        ('_fetch_total', '1'),
      ],
    );
    final String target = name.trim().toLowerCase();
    for (final Map<String, Object?> item in list) {
      final String itemName = (_asString(item['file_name']) ??
              _asString(item['name']) ??
              '')
          .trim()
          .toLowerCase();
      if (itemName != target) continue;
      final String fid = _asString(item['fid']) ??
          _asString(item['file_id']) ??
          (_asInt(item['fid']) != null ? '${item['fid']}' : '');
      if (fid.isNotEmpty) return fid;
    }
    return null;
  }

  /// `file/sort` 列表条目（对齐 iOS 清理辅助里的 GET 列表）。
  Future<List<Map<String, Object?>>> _fileSortList({
    required String cookie,
    required List<(String, String)> query,
  }) async {
    final SpiderHttpResult res = await _bridge.request(
      apiUrl('/1/clouddrive/file/sort', extra: query).toString(),
      options: SpiderHttpOptions(headers: _commonHeaders(cookie)),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    final Object? list = _asMap(json?['data'])?['list'];
    if (list is! List) return const <Map<String, Object?>>[];
    return list
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) => m.cast<String, Object?>())
        .toList(growable: false);
  }

  // ─────────────── JSON 助手 ───────────────

  Map<String, Object?>? _decodeMap(String body) {
    if (body.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(body);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?>? _asMap(Object? v) =>
      v is Map ? v.cast<String, Object?>() : null;

  static String? _asString(Object? v) => v is String ? v : null;

  static int? _asInt(Object? v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
}