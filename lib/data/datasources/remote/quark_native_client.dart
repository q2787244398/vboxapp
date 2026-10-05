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
/// 简化登记（如实）：iOS 的「夸克空间清理 / 转存 fid 缓存 / Set-Cookie 合并」未移植；
/// 本客户端仅做**分享解析 → 文件列表 → 转存 → 取链**主链，Cookie 由调用方提供。
library;

import 'dart:convert';

import '../../../platform/spider/spider_http_bridge.dart';

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
  /// 构造（[bridge] 供测试注入假传输）。
  QuarkNativeClient({SpiderHttpBridge? bridge})
      : _bridge = bridge ?? SpiderHttpBridge();

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
    final List<String> saved = await saveShare(
      pwdId: info.pwdId,
      stoken: stoken,
      file: source,
      cookie: cookie,
    );
    final String fid = saved.first;
    final String url = await getPlayUrl(fileId: fid, cookie: cookie);
    return QuarkPlayResult(url: url, fileName: source.fileName);
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