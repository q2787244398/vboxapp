/// 数据层：UC 网盘原生分享链客户端（批次 F · F-P03，对齐 iOS
/// `CloudDriveManager` 的 UC 分支）。
///
/// 唯一真相源：`vbox/Services/CloudDriveManager.swift`
///   · `ucExtractShareInfo`（L8577）：分享链接 → `pwdId` / `passcode`；
///   · `ucAPIURL`（L8589）：`pc-api.uc.cn` 统一 query（`pr=UCBrowser&fr=pc&sys=darwin&ve=1.8.5`）；
///   · `ucSetCommonHeaders`（L8600）：Cookie / Origin / Referer / UA；
///   · `ucPlaybackHeaders`（L8612）：播放请求头；
///   · `ucGetShareToken`（L8677）：`POST /1/clouddrive/share/sharepage/token`；
///   · `ucGetShareDetail`（L8998）+ `ucCollectAllPlayableFiles`（L8975）：分页递归选集；
///   · `ucEnsureFolderWithCookie`（L8803）：确保根目录 `vbox` 存在；
///   · `ucFindExistingFileInVBox`（L8709）：同名文件去重；
///   · `ucSaveShare`（L8622）：`POST …/sharepage/save`；
///   · `ucGetPlayURL`（L9038）：`POST …/file/v2/play`（4k→low 选流）；
///   · `ucGetDownloadURL`（L9154）+ `stripCDNSpeedLimit`（L9185）：下载直链 + 去限速参数；
///   · `resolveUCPlayURL`（L8366）：主链编排。
///
/// 未移植项（如实登记）：
///   · **TV Token 通道**（`ucGetPlayURLWithTVToken` / `ucListFilesWithTVToken`）——
///     需 `open-api-drive.uc.cn` 的 x-pan 签名与设备指纹，属增强通道；缺省回退
///     `v2/play`（m3u8）→ `download_url`，不影响可播放性；
///   · **WebView / 清理**（`ucDeleteFiles` 等）——空间管理优化，非取链必需。
///
/// 说明：**Set-Cookie 合并**由 HTTP 桥 `SpiderHttpBridge` 的 cookie jar
/// （`storeFromResponse` + 每请求自动附加）等价覆盖 iOS `quarkMergeSetCookie`，
/// 与夸克客户端同一口径。
library;

import 'dart:convert';

import '../../../platform/spider/spider_http_bridge.dart';

/// UC 分享文件条目（对齐 iOS `UCShareFile`）。
class UcShareFile {
  /// 构造。
  const UcShareFile({
    required this.fid,
    required this.fileName,
    this.shareFidToken = '',
    this.pdirFid = '0',
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

/// UC 取链结果（对齐 iOS `PlayResult` 的 UC 子集）。
class UcPlayResult {
  /// 构造。
  const UcPlayResult({
    required this.url,
    required this.headers,
    required this.source,
  });

  /// 播放地址。
  final String url;

  /// 播放请求头（Cookie / UA / Referer / Origin / Accept）。
  final Map<String, String> headers;

  /// 取链来源标记：`v2-play` / `download_url`。
  final String source;
}

/// UC 原生链异常（对齐 iOS `DriveError` 分档文案）。
class UcNativeException implements Exception {
  /// 构造。
  const UcNativeException(this.message);

  /// 文案。
  final String message;

  @override
  String toString() => 'UcNativeException($message)';
}

/// UC 原生分享链客户端。
class UcNativeClient {
  /// 构造（[bridge] 供测试注入假传输）。
  UcNativeClient({SpiderHttpBridge? bridge})
      : _bridge = bridge ?? SpiderHttpBridge();

  /// API 主机（对齐 iOS `ucAPIURL`）。
  static const String apiHost = 'https://pc-api.uc.cn';

  /// 播放清晰度优先级（对齐 iOS `ucGetPlayURL`：4k→low 降序）。
  static const List<String> qualityOrder = <String>[
    '4k', '2k', 'super', 'high', 'normal', 'low',
  ];

  /// 可播放扩展名（对齐 iOS `quarkIsPlayableFileName`，UC 复用同表）。
  static const List<String> playableExts = <String>[
    'mp4', 'mkv', 'mov', 'm3u8', 'avi', 'wmv', 'flv', 'ts', 'mp3', 'm4a',
  ];

  final SpiderHttpBridge _bridge;

  // ─────────────── 静态工具（对齐 iOS 同名函数）───────────────

  /// 解析分享链接 → `(pwdId, passcode)`（对齐 iOS `ucExtractShareInfo`）。
  static ({String pwdId, String passcode}) extractShareInfo(String url) {
    String pwdId = '';
    final RegExpMatch? m = RegExp(r'/s/([^/?#]+)').firstMatch(url);
    if (m != null) {
      pwdId = m.group(1) ?? '';
    } else {
      pwdId = url.trim();
    }
    String passcode = '';
    final Uri? uri = Uri.tryParse(url);
    if (uri != null) {
      for (final MapEntry<String, String> e in uri.queryParameters.entries) {
        if (<String>['pwd', 'passcode', 'password']
            .contains(e.key.toLowerCase())) {
          passcode = e.value;
          break;
        }
      }
    }
    return (pwdId: pwdId, passcode: passcode);
  }

  /// 是否可播放文件（对齐 iOS `quarkIsPlayableFileName`）。
  static bool isPlayableFileName(String name) {
    final String lower = name.toLowerCase();
    return playableExts.any((String e) => lower.endsWith('.$e'));
  }

  /// 统一 API URL（对齐 iOS `ucAPIURL`）。
  static Uri apiUrl(String path, {List<(String, String)> extra = const []}) =>
      Uri.parse('$apiHost$path').replace(queryParameters: <String, String>{
        'pr': 'UCBrowser',
        'fr': 'pc',
        'sys': 'darwin',
        've': '1.8.5',
        for (final (String, String) e in extra) e.$1: e.$2,
      });

  /// 分享 Referer（对齐 iOS `ucShareReferer`）。
  static String shareReferer(String pwdId) => 'https://drive.uc.cn/s/$pwdId';

  /// 播放请求头（对齐 iOS `ucPlaybackHeaders`）。
  static Map<String, String> playbackHeaders(String cookie) => <String, String>{
        if (cookie.isNotEmpty) 'Cookie': cookie,
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 12; HD1900 Build/SKQ1.211113.001; wv) '
                'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
                'Chrome/97.0.4692.98 Mobile Safari/537.36',
        'Referer': 'https://drive.uc.cn/',
        'Origin': 'https://drive.uc.cn',
        'Accept': '*/*',
      };

  /// 去掉 CDN 下载/限速参数（对齐 iOS `stripCDNSpeedLimit`）。
  ///
  /// 仅对下载 CDN（`dl-c-` / 带 `response-content-disposition`）去 `sp` 限速；
  /// 流媒体 CDN 的 `sp` 是 profile ID，不可移除。
  ///
  /// 与 iOS 正则逐条替换的差异：这里按 query 参数逐个筛选，参数出现在首位
  /// 或末位同样能被移除，且不会残留 `?` / `&` 悬挂分隔符。
  static String stripCdnSpeedLimit(String url) {
    final int q = url.indexOf('?');
    if (q < 0) return url;
    final bool isDownloadCdn =
        url.contains('dl-c-') || url.contains('response-content-disposition');
    final int hash = url.indexOf('#', q);
    final String base = url.substring(0, q);
    final String query =
        hash < 0 ? url.substring(q + 1) : url.substring(q + 1, hash);
    final String fragment = hash < 0 ? '' : url.substring(hash);
    final List<String> kept = <String>[];
    for (final String part in query.split('&')) {
      if (part.isEmpty) continue;
      final int eq = part.indexOf('=');
      final String key = (eq < 0 ? part : part.substring(0, eq)).toLowerCase();
      if (key == 'response-content-disposition') continue;
      if (key == 'x-oss-traffic-limit') continue;
      if (key == 'sp' && isDownloadCdn) continue;
      kept.add(part);
    }
    if (kept.isEmpty) return '$base$fragment';
    return '$base?${kept.join('&')}$fragment';
  }

  /// 统一请求头（对齐 iOS `ucSetCommonHeaders`）。
  Map<String, String> _commonHeaders(String cookie, {String? referer}) =>
      <String, String>{
        'Content-Type': 'application/json',
        if (cookie.isNotEmpty) 'Cookie': cookie,
        'Origin': 'https://drive.uc.cn',
        'Referer': referer ?? 'https://drive.uc.cn/',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) uc-cloud-drive/1.8.5 '
                'Chrome/100.0.4896.160 Electron/18.3.5.4-b478491100 '
                'Safari/537.36 Channel/ucpan_other_ch',
      };

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  // ─────────────── 分享 token / 文件列表 ───────────────

  /// 获取分享 `stoken`（对齐 iOS `ucGetShareToken`）。
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
        data: jsonEncode(<String, Object?>{'pwd_id': pwdId, 'passcode': passcode}),
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    if (json == null) {
      throw const UcNativeException('UC 分享 token 响应异常');
    }
    final int code = _asInt(json['code']) ?? 0;
    if (code != 0) {
      throw UcNativeException(
        'UC 分享 token 获取失败：${_asString(json['message']) ?? 'code=$code'}',
      );
    }
    final String st = _asString(_asMap(json['data'])?['stoken']) ?? '';
    if (st.isEmpty) throw const UcNativeException('UC 未返回 stoken');
    return st;
  }

  /// 单页分享文件列表（对齐 iOS `ucGetShareDetail`）。
  Future<List<UcShareFile>> getShareDetail({
    required String pwdId,
    required String stoken,
    required String pdirFid,
    required String cookie,
    int page = 1,
    int size = 100,
  }) async {
    final Uri url = apiUrl(
      '/1/clouddrive/share/sharepage/detail',
      extra: <(String, String)>[
        ('__t', '${_nowMs()}'),
        ('_fetch_banner', '1'),
        ('_fetch_total', '1'),
        ('_page', '$page'),
        ('_size', '$size'),
        ('_sort', 'file_type:asc,file_name:asc'),
        ('pdir_fid', pdirFid),
        ('pwd_id', pwdId),
        ('stoken', stoken),
      ],
    );
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(
        headers: _commonHeaders(cookie, referer: shareReferer(pwdId)),
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    if (json == null) throw const UcNativeException('UC 文件列表响应异常');
    final int code = _asInt(json['code']) ?? 0;
    if (code != 0) {
      throw UcNativeException(
        'UC 文件列表失败：${_asString(json['message']) ?? 'code=$code'}',
      );
    }
    final Object? list = _asMap(json['data'])?['list'];
    if (list is! List) throw const UcNativeException('UC 文件列表为空');
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
          final bool isDir =
              dirFlag ?? (fileFlag == false && fileType == 0);
          return UcShareFile(
            fid: fid,
            fileName: name,
            shareFidToken: token,
            pdirFid: pdirFid,
            isDir: isDir,
          );
        })
        .where((UcShareFile f) => f.fid.isNotEmpty && f.fileName.isNotEmpty)
        .toList(growable: false);
  }

  /// 递归收集全部可播放文件（对齐 iOS `ucCollectAllPlayableFiles`）。
  Future<List<UcShareFile>> collectAllPlayableFiles({
    required String pwdId,
    required String stoken,
    required String cookie,
    String pdirFid = '0',
    int maxPages = 20,
  }) async {
    final List<UcShareFile> out = <UcShareFile>[];
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
    required List<UcShareFile> out,
    required int maxPages,
  }) async {
    int page = 1;
    bool hasMore = true;
    while (hasMore) {
      final List<UcShareFile> files = await getShareDetail(
        pwdId: pwdId,
        stoken: stoken,
        pdirFid: pdirFid,
        cookie: cookie,
        page: page,
      );
      for (final UcShareFile f in files) {
        if (!f.isDir && isPlayableFileName(f.fileName)) out.add(f);
      }
      for (final UcShareFile dir in files.where((UcShareFile f) => f.isDir)) {
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

  /// 分享链接 → 全部可播放文件（对齐 iOS `ucGetFileList`，三层容错）。
  Future<List<UcShareFile>> getFileList({
    required String shareUrl,
    required String cookie,
  }) async {
    final ({String pwdId, String passcode}) info = extractShareInfo(shareUrl);
    if (info.pwdId.isEmpty) {
      throw const UcNativeException('无法识别的分享链接');
    }
    // 第一层：刷新 Cookie（失败则用原始 Cookie 继续）。
    try {
      await ensureFolder(cookie: cookie);
    } on UcNativeException {
      // 忽略（对齐 iOS：ensureFolder 失败仍继续尝试）。
    }
    final String stoken = await getShareToken(
      pwdId: info.pwdId,
      passcode: info.passcode,
      cookie: cookie,
    );
    // 第二层：stoken 失效刷新重试；第三层：明确报错。
    return _collectWithRetry(
      pwdId: info.pwdId,
      passcode: info.passcode,
      stoken: stoken,
      cookie: cookie,
    );
  }

  Future<List<UcShareFile>> _collectWithRetry({
    required String pwdId,
    required String passcode,
    required String stoken,
    required String cookie,
  }) async {
    try {
      return await collectAllPlayableFiles(
        pwdId: pwdId,
        stoken: stoken,
        cookie: cookie,
      );
    } on UcNativeException catch (e) {
      if (!_isTokenError(e.message)) rethrow;
      final String newStoken = await getShareToken(
        pwdId: pwdId,
        passcode: passcode,
        cookie: cookie,
      );
      try {
        return await collectAllPlayableFiles(
          pwdId: pwdId,
          stoken: newStoken,
          cookie: cookie,
        );
      } on UcNativeException {
        throw const UcNativeException('UC Cookie 已过期，请重新扫码登录');
      }
    }
  }

  static bool _isTokenError(String message) =>
      message.contains('非法token') || message.contains('token');

  // ─────────────── 转存（vbox 目录 + 去重 + save）───────────────

  /// 确保根目录 `vbox` 存在，返回其 fid（对齐 iOS `ucEnsureFolderWithCookie`）。
  Future<String> ensureFolder({required String cookie}) async {
    final List<(String, String)> sortQuery = <(String, String)>[
      ('pdir_fid', '0'),
      ('_sort', 'file_type:asc,file_name:asc'),
      ('_page', '1'),
      ('_size', '100'),
      ('_fetch_total', '1'),
    ];
    final Map<String, Object?>? listJson = await _fileSort(
      cookie: cookie,
      query: sortQuery,
    );
    _throwIfInvalidCookie(listJson, 'list');
    final String? found = _findVboxFid(listJson);
    if (found != null) return found;

    // 创建 vbox
    final SpiderHttpResult createRes = await _bridge.request(
      apiUrl('/1/clouddrive/file').toString(),
      options: SpiderHttpOptions(
        method: 'POST',
        headers: _commonHeaders(cookie),
        data: jsonEncode(<String, Object?>{
          'pdir_fid': '0',
          'file_name': 'vbox',
          'dir': true,
          'dir_path': '',
        }),
      ),
    );
    final Map<String, Object?>? createJson = _decodeMap(createRes.content);
    if (createJson != null) {
      final int code = _asInt(createJson['code']) ?? 0;
      if (code == 0) {
        final String fid =
            _asString(_asMap(createJson['data'])?['fid']) ?? '';
        if (fid.isNotEmpty) return fid;
      } else if (code != 23008) {
        throw UcNativeException(
          'UC: Cookie 可能已失效，请重新登录 (create code=$code '
          'msg=${_asString(createJson['message']) ?? ''})',
        );
      }
    }

    // 已存在（code=23008）→ 重新 list
    final Map<String, Object?>? reJson = await _fileSort(
      cookie: cookie,
      query: sortQuery,
    );
    _throwIfInvalidCookie(reJson, 're-list');
    final String? reFound = _findVboxFid(reJson);
    if (reFound != null) return reFound;
    throw const UcNativeException('UC: 无法找到或创建 vbox 文件夹');
  }

  Future<Map<String, Object?>?> _fileSort({
    required String cookie,
    required List<(String, String)> query,
  }) async {
    final SpiderHttpResult res = await _bridge.request(
      apiUrl('/1/clouddrive/file/sort', extra: query).toString(),
      options: SpiderHttpOptions(headers: _commonHeaders(cookie)),
    );
    return _decodeMap(res.content);
  }

  void _throwIfInvalidCookie(Map<String, Object?>? json, String stage) {
    if (json == null) return;
    final int code = _asInt(json['code']) ?? 0;
    if (code == 10001 || code == 10002 || code == 10003) {
      throw UcNativeException('UC: Cookie 可能已失效，请重新登录 ($stage code=$code)');
    }
  }

  /// 在 `data.list` / `data`（数组）中查 `vbox` 目录 fid。
  static String? _findVboxFid(Map<String, Object?>? json) {
    if (json == null) return null;
    final Object? data = json['data'];
    final Object? list = data is Map ? data['list'] : data;
    if (list is! List) return null;
    for (final Object? raw in list) {
      final Map<String, Object?>? f = _asMap(raw);
      if (f == null) continue;
      if (_asString(f['file_name']) == 'vbox') {
        final String fid = _asString(f['fid']) ?? '';
        if (fid.isNotEmpty) return fid;
      }
    }
    return null;
  }

  /// 检查 vbox 目录中是否已有同名文件（对齐 iOS `ucFindExistingFileInVBox`）。
  Future<String?> findExistingFileInVBox({
    required String fileName,
    required String folderId,
    required String cookie,
  }) async {
    final Map<String, Object?>? json = await _fileSort(
      cookie: cookie,
      query: <(String, String)>[
        ('pdir_fid', folderId),
        ('_sort', 'file_type:asc,file_name:asc'),
        ('_page', '1'),
        ('_size', '50'),
        ('_fetch_total', '1'),
      ],
    );
    if (json == null) return null;
    final Object? data = json['data'];
    final Object? list = data is Map ? data['list'] : data;
    if (list is! List) return null;
    for (final Object? raw in list) {
      final Map<String, Object?>? f = _asMap(raw);
      if (f == null) continue;
      if (_asString(f['file_name']) == fileName) {
        final String fid = _asString(f['fid']) ?? '';
        if (fid.isNotEmpty) return fid;
      }
    }
    return null;
  }

  /// 转存分享文件到 `folderId`，返回顶层 fid 列表（对齐 iOS `ucSaveShare`）。
  Future<List<String>> saveShare({
    required String pwdId,
    required String stoken,
    required UcShareFile file,
    required String folderId,
    required String cookie,
  }) async {
    final SpiderHttpResult res = await _bridge.request(
      apiUrl(
        '/1/clouddrive/share/sharepage/save',
        extra: <(String, String)>[('__t', '${_nowMs()}')],
      ).toString(),
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
        }),
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    if (json == null) throw const UcNativeException('UC 转存失败：响应异常');
    final int status = _asInt(json['status']) ?? 0;
    if (status != 200 && status != 0) {
      throw UcNativeException(
        'UC 转存失败：${_asString(json['message']) ?? _asString(json['msg']) ?? '状态码：$status'}',
      );
    }
    final int code = _asInt(json['code']) ?? 0;
    if (code != 0) {
      throw UcNativeException(
        'UC 转存失败：${_asString(json['message']) ?? _asString(json['msg']) ?? '错误码：$code'}',
      );
    }
    final List<String> ids = _extractSavedFids(_asMap(json['data']));
    if (ids.isEmpty) {
      throw const UcNativeException('UC 转存成功但未返回已转存 fid');
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

  // ─────────────── 取链 ───────────────

  /// `POST …/file/v2/play` 转码流（对齐 iOS `ucGetPlayURL`，4k→low 选流）。
  Future<String> getPlayUrl({
    required String fileId,
    required String cookie,
  }) async {
    final SpiderHttpResult res = await _bridge.request(
      apiUrl(
        '/1/clouddrive/file/v2/play',
        extra: <(String, String)>[
          ('pr', 'UCBrowser'),
          ('fr', 'pc'),
          ('sys', 'ios'),
          ('ve', '1.8.5'),
        ],
      ).toString(),
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
    if (json == null) throw const UcNativeException('UC v2/play 响应异常');
    final int code = _asInt(json['code']) ?? 0;
    if (code != 0) {
      throw UcNativeException(
        'UC v2/play 失败: ${_asString(json['message']) ?? 'code=$code'}',
      );
    }
    final Object? videos = _asMap(json['data'])?['video_list'];
    if (videos is List) {
      for (final String quality in qualityOrder) {
        for (final Object? item in videos) {
          final Map<String, Object?>? m = _asMap(item);
          if (m == null) continue;
          final Map<String, Object?>? info = _asMap(m['video_info']);
          if (_asString(info?['resolution']) != quality) continue;
          final bool accessable = m['accessable'] as bool? ?? true;
          final String u = _asString(info?['url']) ?? '';
          if (accessable && u.isNotEmpty) return u;
        }
      }
    }
    final String playUrl =
        _asString(_asMap(json['data'])?['play_url']) ??
            _asString(json['play_url']) ??
            '';
    if (playUrl.isNotEmpty) return playUrl;
    throw const UcNativeException('UC: 未返回播放地址');
  }

  /// `POST …/file/download` 下载直链（对齐 iOS `ucGetDownloadURL` + 去限速）。
  Future<String> getDownloadUrl({
    required String fileId,
    required String cookie,
  }) async {
    final SpiderHttpResult res = await _bridge.request(
      apiUrl('/1/clouddrive/file/download').toString(),
      options: SpiderHttpOptions(
        method: 'POST',
        headers: _commonHeaders(cookie),
        data: jsonEncode(<String, Object?>{
          'fids': <String>[fileId],
        }),
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    if (json == null) throw const UcNativeException('UC download_url 响应异常');
    final int code = _asInt(json['code']) ?? 0;
    if (code != 0) {
      throw UcNativeException(
        'UC download_url 获取失败：${_asString(json['message']) ?? 'code=$code'}',
      );
    }
    final Object? data = json['data'];
    if (data is List && data.isNotEmpty) {
      final String u = _asString(_asMap(data.first)?['download_url']) ?? '';
      if (u.isNotEmpty) return stripCdnSpeedLimit(u);
    }
    final String u = _asString(_asMap(data)?['download_url']) ?? '';
    if (u.isNotEmpty) return stripCdnSpeedLimit(u);
    return '';
  }

  /// 分享链接 → 取链（对齐 iOS `resolveUCPlayURL` 主链；TV Token/清理未移植）。
  Future<UcPlayResult> resolvePlayUrl({
    required String shareUrl,
    required String cookie,
    String? preferredFid,
  }) async {
    final ({String pwdId, String passcode}) info = extractShareInfo(shareUrl);
    if (info.pwdId.isEmpty) {
      throw const UcNativeException('无法识别的分享链接');
    }
    final String folderId = await ensureFolder(cookie: cookie);
    final String stoken = await getShareToken(
      pwdId: info.pwdId,
      passcode: info.passcode,
      cookie: cookie,
    );
    final List<UcShareFile> files = await _collectWithRetry(
      pwdId: info.pwdId,
      passcode: info.passcode,
      stoken: stoken,
      cookie: cookie,
    );
    if (files.isEmpty) {
      throw const UcNativeException('UC 分享内未找到可播放视频');
    }
    final UcShareFile source = (preferredFid != null && preferredFid.isNotEmpty)
        ? files.firstWhere(
            (UcShareFile f) => f.fid == preferredFid,
            orElse: () => files.first,
          )
        : files.first;

    // 转存前查重，避免重复转存（对齐 iOS `ucResolveUCShareFile.trySave`）。
    final String? existing = await findExistingFileInVBox(
      fileName: source.fileName,
      folderId: folderId,
      cookie: cookie,
    );
    final String fileId;
    if (existing != null) {
      fileId = existing;
    } else {
      final List<String> ids = await saveShare(
        pwdId: info.pwdId,
        stoken: stoken,
        file: source,
        folderId: folderId,
        cookie: cookie,
      );
      fileId = ids.first;
    }

    // 优先级：v2/play（m3u8）→ download_url（对齐 iOS；TV Token 未移植）。
    String transcode = '';
    try {
      transcode = await getPlayUrl(fileId: fileId, cookie: cookie);
    } on UcNativeException {
      // 忽略，继续尝试 download_url。
    }
    String download = '';
    try {
      download = await getDownloadUrl(fileId: fileId, cookie: cookie);
    } on UcNativeException {
      // 忽略，可能 v2/play 已可用。
    }
    final String url =
        transcode.isNotEmpty ? transcode : download;
    if (url.isEmpty) {
      throw const UcNativeException('UC: download_url 与转码地址均为空');
    }
    return UcPlayResult(
      url: url,
      headers: playbackHeaders(cookie),
      source: transcode.isNotEmpty ? 'v2-play' : 'download_url',
    );
  }

  // ─────────────── JSON 助手 ───────────────

  static Map<String, Object?>? _decodeMap(String body) {
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

  static String? _asString(Object? v) =>
      v is String ? v : (v is num ? '$v' : null);

  static int? _asInt(Object? v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
}