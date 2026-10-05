/// 数据层：百度网盘 iBox 本机链客户端（批次 F · F-P02，C1 + C2 段）。
///
/// 唯一真相源：`vbox/Services/CloudDriveManager.swift`
///   · C1：`parseBaiduToken`（L4471）粘贴串 → (cookie, BDUSS)；
///     `baiduMergeCookieStrings`（L5619）多段 Cookie 合并（忽略属性名）；
///     `baiduErrorMessage`（L5391）errno → 中文文案；
///     `baiduExtractShareMeta`（L5906-L6376）分享验证链
///     `wap/init → (share/verify) → 桌面分享页 → gettemplatevariable → share/list(root + dirs)`；
///   · C2：`baiduFetchUserBdstokenLocal`（L4684）用户态 bdstoken；
///     `baiduEnsureVboxFolderLocal`（L4832）建 `/vbox` 转存目录；
///     `baiduFindExistingVboxPath`（L5034）/`baiduWaitForTransferredPath`（L5147）落盘确认；
///     `baiduTransferFileOnDevice`（L5169）`share/transfer` 转存；
///     `baiduRefreshTransferSekey`（L5320）账号态 verify 刷新 sekey；
///     `baiduGetDLNADlinkOnDevice`（L5429）`api/mediainfo` DLNA 取链；
///     `baiduGetLocatedownloadOnDevice`（L5477）`pcs/file?method=locatedownload` 原画取链。
///
/// C1 只做**分享上下文 + 多文件选集列表**；C2 补**转存链（建目录/转存/等待落盘）+
/// DLNA 取链（mediainfo/locatedownload）**；WebView 回退见 C3（Web-R1）。
///
/// 实现说明（对齐口径）：直接使用 [SpiderHttpTransport]（**不经** `SpiderHttpBridge`
/// 的 cookie jar）——因为 iOS 明确要求 `share/verify` **不带任何 Cookie**，而桥层会
/// 自动附加 jar cookie；传输层同时显式返回 `setCookies`，便于按 iOS
/// `baiduMergeCookieStrings` 语义手动合并。
///
/// 未移植项（如实登记）：iOS 在 URLSession 失败时回退 WKWebView XHR
/// （create/list/transfer/bdstoken）——属 C3（Web-R1），本段不实现，失败即抛错。
///
/// C3 回退点（对齐 iOS 调用点，待 WebView 桥接入后逐点补）：
///   · `fetchUserBdstoken` ← `baiduFetchUserBdstokenViaWebView`（CloudDriveManager L4724）；
///   · `ensureTransferDir`  ← `baiduCreateFolderViaWebView`（L4873）+ `baiduCanListTransferDirViaWebView`（L4885）；
///   · `findExistingVboxPath` ← `baiduFindExistingVboxPathViaWebView`（L5077/L5083/L5088）；
///   · `transferFile`       ← `baiduTransferFileViaWebView`（L5224/L5240）。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../../../platform/spider/spider_http_bridge.dart';
import '../local/prefs_manager.dart';

/// 百度分享文件条目（对齐 iOS `BaiduFileItem`）。
class BaiduFileItem {
  /// 构造。
  const BaiduFileItem({required this.fsId, required this.name});

  /// 文件 ID。
  final String fsId;

  /// 文件名。
  final String name;

  /// 是否可播放视频（对齐 iOS `baiduIsPlayableVideoFileName`）。
  bool get isPlayableVideo =>
      BaiduIBoxClient.isPlayableVideoFileName(name);
}

/// 分享上下文（对齐 iOS `BaiduShareContext` 的核心字段）。
class BaiduShareMeta {
  /// 构造。
  const BaiduShareMeta({
    required this.shareid,
    required this.shareUk,
    required this.bdstoken,
    required this.surl,
    required this.cookie,
    required this.files,
    required this.randsk,
  });

  /// 分享 ID。
  final String shareid;

  /// 分享者 uk。
  final String shareUk;

  /// 用户态 bdstoken（可能为空）。
  final String bdstoken;

  /// 短链 surl（含前导 `1`）。
  final String surl;

  /// 链路过程中合并出的 Cookie。
  final String cookie;

  /// 可播放文件列表（选集）。
  final List<BaiduFileItem> files;

  /// 提取码验证后的 `randsk`（目录列举需用）。
  final String randsk;
}

/// 百度取链结果（对齐 iOS `PlayResult` 的百度子集）。
class BaiduPlayResult {
  /// 构造。
  const BaiduPlayResult({
    required this.url,
    required this.headers,
    required this.source,
  });

  /// 播放地址。
  final String url;

  /// 播放请求头（Cookie / UA / Referer / Origin）。
  final Map<String, String> headers;

  /// 取链来源标记（诊断 / 缓存用）。
  final String source;
}

/// 百度 iBox 本机链异常。
class BaiduIBoxException implements Exception {
  /// 构造。
  const BaiduIBoxException(this.message);

  /// 文案。
  final String message;

  @override
  String toString() => 'BaiduIBoxException($message)';
}

/// 百度 iBox 本机链客户端（C1：分享上下文 + 文件列表）。
class BaiduIBoxClient {
  /// 构造（[transport] / [prefs] 供测试注入）。
  BaiduIBoxClient({SpiderHttpTransport? transport, PrefsManager? prefs})
      : _transport = transport ?? IoSpiderHttpTransport(),
        _prefs = prefs;

  /// 分享上下文缓存契约键（对齐 iOS `baidu_share_context_cache_v1`）。
  static const String shareContextCacheKey = 'baidu_share_context_cache_v1';

  /// 分享上下文缓存 TTL（近似 iOS `storeShareContext` 的默认有效期）。
  static const Duration shareContextTtl = Duration(minutes: 30);

  /// Mac Chrome UA（对齐 iOS iBox：分享验证 / share/list 用它，非 iOS Safari）。
  static const String webUA =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

  /// PCS 客户端 UA（对齐 iOS `baiduPCSUserAgent`：mediainfo / locatedownload 用）。
  static const String pcsUserAgent =
      'Mozilla/5.0 (Linux; Android 12; HD1900 Build/SKQ1.211113.001) '
      'AppleWebKit/537.36 (KHTML, like Gecko)'
      '&channel=android_12_HD1900_bdnetdisktv_1025538l&version=1.21.1'
      '&network_type=wifi&app_id=250528&size=c1080_u1600';

  /// 转存目标目录（对齐 iOS `baiduIBoxTransferDir`：百度真实根路径 `/vbox`）。
  static const String transferDir = '/vbox';

  /// 转存落盘轮询上限（对齐 iOS `1...8`）。
  static const int transferWaitAttempts = 8;

  /// 可播放视频扩展名（对齐 iOS `baiduIsPlayableVideoFileName`）。
  static const List<String> playableVideoExts = <String>[
    'mp4', 'mkv', 'mov', 'm4v', 'avi', 'wmv', 'flv', 'ts', 'm2ts', 'mts',
    'webm', 'mpg', 'mpeg', '3gp', 'rm', 'rmvb', 'asf', 'f4v', 'm3u8',
  ];

  final SpiderHttpTransport _transport;
  final PrefsManager? _prefs;

  // ─────────────── 静态工具（对齐 iOS 同名函数）───────────────

  /// 粘贴串 → `(cookie, BDUSS)`（对齐 iOS `parseBaiduToken`）。
  static ({String cookie, String bduss}) parseToken(String raw) {
    String input = raw.trim();
    if (input.toLowerCase().startsWith('cookie:')) {
      input = input.substring('cookie:'.length).trim();
    }
    String normalizeCookie(String s) => s
        .replaceAll('\n', '; ')
        .replaceAll('\r', '; ')
        .replaceAll(RegExp(r'\s*;\s*'), '; ')
        .replaceAll(RegExp(r';+\s*$'), '');

    if (RegExp(r'BDUSS=([^;|]+)').hasMatch(input)) {
      final String normalized = normalizeCookie(input);
      final RegExpMatch? m = RegExp(r'BDUSS=([^;|]+)').firstMatch(normalized);
      final String bduss = (m?.group(1) ?? '').trim();
      if (bduss.isNotEmpty) return (cookie: normalized, bduss: bduss);
    }
    if (input.contains('|')) {
      final String cleaned = input.replaceAll(RegExp(r'^BDUSS='), '');
      final List<String> parts = cleaned.split('|');
      final String bduss = parts[0].trim();
      String cookie = 'BDUSS=$bduss';
      if (parts.length >= 2) {
        final String stoken =
            parts[1].replaceAll(RegExp(r'^STOKEN='), '').trim();
        cookie += '; STOKEN=$stoken';
      }
      return (cookie: cookie, bduss: bduss);
    }
    final String bduss = input.replaceAll('BDUSS=', '').trim();
    return (cookie: 'BDUSS=$bduss', bduss: bduss);
  }

  /// 多段 Cookie 合并（对齐 iOS `baiduMergeCookieStrings`：忽略属性名，后到覆盖）。
  static String mergeCookieStrings(List<String> cookies) {
    const Set<String> ignored = <String>{
      'expires', 'path', 'domain', 'max-age', 'secure', 'httponly', 'samesite',
    };
    final List<String> keys = <String>[];
    final Map<String, (String, String)> values = <String, (String, String)>{};
    for (final String cookie in cookies) {
      if (cookie.isEmpty) continue;
      final String normalized = cookie
          .replaceAllMapped(
            RegExp(r',\s*([A-Za-z_][A-Za-z0-9_\-]*)='),
            (Match m) => ';\n${m.group(1)}=',
          )
          .replaceAll('\n', ';');
      for (final String part in normalized.split(';')) {
        final String item = part.trim();
        final int eq = item.indexOf('=');
        if (eq <= 0) continue;
        final String name = item.substring(0, eq).trim();
        final String value = item.substring(eq + 1).trim();
        if (name.isEmpty || value.isEmpty) continue;
        final String key = name.toLowerCase();
        if (ignored.contains(key)) continue;
        if (!values.containsKey(key)) keys.add(key);
        values[key] = (name, value);
      }
    }
    return keys
        .where(values.containsKey)
        .map((String k) => '${values[k]!.$1}=${values[k]!.$2}')
        .join('; ');
  }

  /// errno → 中文文案（对齐 iOS `baiduErrorMessage`）。
  static String errorMessage(int errno, [String? fallback]) => switch (errno) {
        0 => '成功',
        -9 => '提取码错误',
        200025 => '分享验证态未绑定当前账号，请重新验证后转存',
        -8 => '目标目录或文件已存在',
        -7 || -10 => '账号登录态已过期，请重新扫码登录',
        -6 => '身份验证失败，请重新登录百度网盘',
        -4 || 4 => '需要图形验证码或安全验证',
        2 => '参数错误或分享信息不完整',
        5 => '分享链接不存在或已失效',
        10 => '分享内容不存在或已被删除',
        _ => fallback ?? '百度错误 errno=$errno',
      };

  /// 提取 surl（对齐 iOS：优先 `/s/1xxx` 保留前导 1）。
  static String? extractSurl(String shareUrl) {
    final RegExpMatch? m1 = RegExp(r'/s/1([^/?]+)').firstMatch(shareUrl);
    if (m1 != null) return '1${m1.group(1)}';
    final RegExpMatch? m2 = RegExp(r'/s/([^/?]+)').firstMatch(shareUrl);
    return m2?.group(1);
  }

  /// 提取提取码（对齐 iOS `extractBaiduPwd`）。
  static String? extractPwd(String shareUrl) {
    final RegExpMatch? m = RegExp(r'[?&]pwd=([^&]+)').firstMatch(shareUrl);
    return m?.group(1);
  }

  /// iOS `baiduShortSurl`：去掉 surl 前导 `1`。
  static String shortSurl(String surl) =>
      surl.startsWith('1') ? surl.substring(1) : surl;

  // ─────────────── 静态工具（C2，对齐 iOS 同名函数）───────────────

  /// 是否为可播放视频（对齐 iOS `baiduIsPlayableVideoFileName`）。
  static bool isPlayableVideoFileName(String fileName) {
    final String lower = fileName.toLowerCase();
    return playableVideoExts.any((String e) => lower.endsWith('.$e'));
  }

  /// 取 Cookie 指定字段值（对齐 iOS `baiduCookieValue`；空值视为不存在）。
  static String? cookieValue(String cookie, String name) {
    final String lowerName = name.toLowerCase();
    for (final String part in cookie.split(';')) {
      final String item = part.trim();
      final int eq = item.indexOf('=');
      if (eq <= 0) continue;
      final String key = item.substring(0, eq).trim().toLowerCase();
      final String value = item.substring(eq + 1).trim();
      if (key == lowerName && value.isNotEmpty) return value;
    }
    return null;
  }

  /// 剔除分享态字段，仅保留账号态 Cookie（对齐 iOS `baiduPureAccountCookie`）。
  ///
  /// 私域接口（gettemplatevariable / api/create / filemanager / api/list）只允许
  /// 账号态 Cookie；混入 BDCLND 等会触发 errno=-6/-9。
  static String pureAccountCookie(String cookie) {
    if (cookie.isEmpty) return cookie;
    const Set<String> drop = <String>{
      'bdclnd', 'bdclnd_bfess', 'share_pwd', 'share_pwd_bfess',
    };
    final String merged = mergeCookieStrings(<String>[cookie]);
    return merged
        .split(';')
        .map((String p) => p.trim())
        .where((String item) {
          final int eq = item.indexOf('=');
          if (eq <= 0) return false;
          final String name = item.substring(0, eq).trim().toLowerCase();
          return !drop.contains(name);
        })
        .join('; ');
  }

  /// 规范化 PCS Cookie（对齐 iOS `normalizeBaiduPCSCookie`）。
  static String normalizePCSCookie(String raw) => raw
      .trim()
      .replaceAll('\n', '; ')
      .replaceAll('\r', '; ')
      .replaceAll(RegExp(r'\s*;\s*'), '; ')
      .replaceAll(RegExp(r';+\s*$'), '');

  /// 严格查询编码（对齐 iOS `baiduQueryEncoded`：`urlQueryAllowed` 去掉 `&+=?#`）。
  static String queryEncodeStrict(String value) {
    const String allowed = "-._~!$'()*,;:@/?";
    final StringBuffer sb = StringBuffer();
    for (final int rune in value.runes) {
      final String ch = String.fromCharCode(rune);
      final bool keep =
          RegExp(r'[A-Za-z0-9]').hasMatch(ch) || allowed.contains(ch);
      sb.write(keep ? ch : Uri.encodeComponent(ch));
    }
    return sb.toString();
  }

  /// 从 HTML 抓用户态 bdstoken（对齐 iOS `baiduExtractBdstokenFromHTML`）。
  static String? extractBdstokenFromHTML(String html) {
    const List<String> patterns = <String>[
      r'''["']bdstoken["']\s*:\s*["']([^"']+)["']''',
      r'''bdstoken\s*=\s*["']([^"']+)["']''',
      r'bdstoken=([A-Za-z0-9_\-%.]+)',
    ];
    for (final String p in patterns) {
      final RegExpMatch? m =
          RegExp(p, caseSensitive: false).firstMatch(html);
      if (m != null && m.group(1) != null) {
        final String token = m.group(1)!.trim();
        if (token.isNotEmpty) {
          try {
            return Uri.decodeComponent(token);
          } catch (_) {
            return token;
          }
        }
      }
    }
    return null;
  }

  // ─────────────── 分享上下文 + 文件列表（C1 主链）───────────────

  /// 分享链接 → 全部可播放文件（对齐 iOS `baiduGetFileList`）。
  Future<List<BaiduFileItem>> getFileList({
    required String shareUrl,
    required String cookie,
  }) async =>
      (await extractShareMeta(
        shareUrl: shareUrl,
        cookie: cookie,
        returnAll: true,
      ))
          .files;

  /// 分享验证链（对齐 iOS `baiduExtractShareMeta`，C1 范围）。
  Future<BaiduShareMeta> extractShareMeta({
    required String shareUrl,
    required String cookie,
    bool returnAll = false,
  }) async {
    final String? surl = extractSurl(shareUrl);
    if (surl == null || surl.isEmpty) {
      throw const BaiduIBoxException('无法识别的分享链接');
    }
    final String? pwd = extractPwd(shareUrl);
    final String contextKey = _shareContextKey(shareUrl, cookie);

    if (!returnAll) {
      final BaiduShareMeta? cached = await _cachedContext(contextKey);
      if (cached != null) return cached;
    }

    final String shortSurl = shortSurlOf(surl);
    final String initUrl = 'https://pan.baidu.com/wap/init?surl=$shortSurl';
    final String desktopShareUrl = 'https://pan.baidu.com/s/1$shortSurl';

    String iBoxCookie = cookie;
    String shareid = '';
    String shareUk = '';
    String bdstoken = '';
    String randskForList = '';
    final List<BaiduFileItem> files = <BaiduFileItem>[];

    // ① GET /wap/init
    final _Resp initResp = await _request(
      initUrl,
      headers: <String, String>{
        'Cookie': iBoxCookie,
        'User-Agent': webUA,
        'Referer': 'https://pan.baidu.com/',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
      timeout: 18,
    );
    iBoxCookie = mergeCookieStrings(<String>[iBoxCookie, ...initResp.setCookies]);
    _applyYunDataHtml(initResp.text, files);

    // ② POST /share/verify（对齐 iOS：**不带任何 Cookie**）
    if (pwd != null && pwd.isNotEmpty) {
      final String encodedPwd = queryEncodeStrict(pwd);
      final String verifyUrl =
          'https://pan.baidu.com/share/verify?t=${DateTime.now().millisecondsSinceEpoch}'
          '&surl=$shortSurl&channel=chunlei&web=1&app_id=250528'
          '&bdstoken=&clienttype=0';
      final String verifyBody =
          'pwd=$encodedPwd&vcode=&vcode_str=&channel=chunlei&web=1'
          '&app_id=250528&clienttype=0&bdstoken=';
      final _Resp verifyResp = await _request(
        verifyUrl,
        method: 'POST',
        headers: <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          'Cookie': '',
          'User-Agent': webUA,
          'Origin': 'https://pan.baidu.com',
          'Referer': 'https://pan.baidu.com/',
          'Accept': '*/*',
          'Accept-Language': 'zh-Hans-001;q=1.0',
        },
        body: verifyBody,
        timeout: 18,
      );
      iBoxCookie = mergeCookieStrings(<String>[iBoxCookie, ...verifyResp.setCookies]);
      final Map<String, Object?>? vjson = _decodeMap(verifyResp.text);
      final int? errno = _asInt(vjson?['errno']);
      if (vjson == null || errno == null) {
        throw BaiduIBoxException(
          '百度 iBox 验证返回非 JSON：${_preview(verifyResp.text)}',
        );
      }
      if (errno != 0) {
        throw BaiduIBoxException(
          '百度 iBox 验证失败：${errorMessage(errno, _asString(vjson['errmsg']) ?? _asString(vjson['show_msg']))}',
        );
      }
      final String? rawRandsk = _asString(vjson['randsk']);
      if (rawRandsk != null && rawRandsk.isNotEmpty) {
        final String decoded = Uri.decodeComponent(rawRandsk);
        randskForList = decoded;
        iBoxCookie = mergeCookieStrings(<String>[
          iBoxCookie,
          'BDCLND=$rawRandsk; randsk=$decoded',
        ]);
      }
    }

    // ②.5 桌面分享页（带 BDCLND/randsk 后再抓，否则会在验证页循环）
    final _Resp desktopResp = await _request(
      desktopShareUrl,
      headers: <String, String>{
        'Cookie': iBoxCookie,
        'User-Agent': webUA,
        'Referer': initUrl,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
      timeout: 18,
    );
    iBoxCookie = mergeCookieStrings(<String>[iBoxCookie, ...desktopResp.setCookies]);
    _applyYunDataHtml(desktopResp.text, files);

    // ②.6 gettemplatevariable（分享页上下文之后，桌面分享页 Referer）
    final _Resp tplResp = await _request(
      'https://pan.baidu.com/api/gettemplatevariable'
      '?clienttype=0&app_id=250528&web=1&bdstoken=$bdstoken'
      '&fields=${Uri.encodeComponent('["bdstoken","token","uk","username","shareid","share_id","share_uk","sign","timestamp","file_list","filelist","list","records","shareinfo","share_info","yunData"]')}',
      headers: <String, String>{
        'Cookie': iBoxCookie,
        'User-Agent': webUA,
        'Referer': desktopShareUrl,
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'X-Requested-With': 'XMLHttpRequest',
      },
      timeout: 15,
    );
    iBoxCookie = mergeCookieStrings(<String>[iBoxCookie, ...tplResp.setCookies]);
    final Map<String, Object?>? tpl = _decodeMap(tplResp.text);
    if (tpl != null) {
      final String tBd = _deepString(tpl, <String>{'bdstoken'});
      final String tShareid =
          _deepString(tpl, <String>{'shareid', 'share_id'});
      final String tUk = _deepString(tpl, <String>{'share_uk', 'uk'});
      final List<BaiduFileItem> tFiles = _deepFiles(tpl);
      if (bdstoken.isEmpty && tBd.isNotEmpty) bdstoken = tBd;
      if (shareid.isEmpty && tShareid.isNotEmpty) shareid = tShareid;
      if (shareUk.isEmpty && tUk.isNotEmpty) shareUk = tUk;
      if (files.isEmpty && tFiles.isNotEmpty) files.addAll(tFiles);
    }

    // ③ share/list：root-shorturl（不带账号态 Cookie）
    final String encodedShortSurl = _queryEncoded(shortSurl);
    final String rootUrl =
        'https://pan.baidu.com/share/list?app_id=250528&bdstoken=&channel=chunlei'
        '&clienttype=0&desc=1&num=20&order=time&page=1&root=1'
        '&shorturl=$encodedShortSurl&showempty=0&view_mode=1&web=1';
    final List<String> dirsToLoad = <String>[];
    String lastListError = '';

    Future<Map<String, Object?>?> requestShareList(
      String listUrl, {
      required bool includeAccountCookie,
    }) async {
      final _Resp r = await _request(
        listUrl,
        headers: <String, String>{
          'Cookie': _cookieForShareList(
            iBoxCookie,
            includeAccount: includeAccountCookie,
          ),
          'User-Agent': webUA,
          'Referer': 'https://pan.baidu.com/',
          'Accept': '*/*',
          'Accept-Language': 'zh-Hans-001;q=1.0',
          'Origin': 'https://pan.baidu.com',
        },
        timeout: 18,
      );
      iBoxCookie = mergeCookieStrings(<String>[iBoxCookie, ...r.setCookies]);
      final Map<String, Object?>? json = _decodeMap(r.text);
      if (json == null) {
        lastListError = _preview(r.text);
        return null;
      }
      final int errno = _asInt(json['errno']) ?? 0;
      if (errno != 0) {
        lastListError =
            errorMessage(errno, _asString(json['errmsg']) ?? _asString(json['show_msg']));
        return null;
      }
      return json;
    }

    final Map<String, Object?>? rootJson =
        await requestShareList(rootUrl, includeAccountCookie: false);
    if (rootJson != null) {
      final Map<String, Object?> root =
          _asMap(rootJson['data']) ?? rootJson;
      final String rootShareid =
          _asString(root['share_id']) ?? _asString(root['shareid']) ?? '';
      final String rootUk =
          _asString(root['uk']) ?? _asString(root['share_uk']) ?? '';
      if (rootShareid.isNotEmpty) shareid = rootShareid;
      if (rootUk.isNotEmpty) shareUk = rootUk;
      final Object? rawList = root['list'];
      if (rawList is List) {
        final List<Map<String, Object?>> items =
            rawList.whereType<Map<Object?, Object?>>().map((Map<Object?, Object?> m) => m.cast<String, Object?>()).toList();
        files.addAll(_parsePlayableFiles(items));
        dirsToLoad.addAll(items
            .where(_isDirectory)
            .map((Map<String, Object?> i) => _asString(i['path']) ?? '')
            .where((String p) => p.isNotEmpty));
      }
    }

    // ③.5 子目录列举（需 shareid/uk/randsk；对齐 iOS 上限 30 个目录）
    if (shareid.isNotEmpty && shareUk.isNotEmpty && randskForList.isNotEmpty) {
      final Set<String> seen = <String>{};
      int index = 0;
      while (index < dirsToLoad.length && index < 30) {
        final String dir = dirsToLoad[index];
        index++;
        if (dir.isEmpty || seen.contains(dir)) continue;
        seen.add(dir);
        final String dirUrl =
            'https://pan.baidu.com/share/list?app_id=250528&bdstoken=&channel=chunlei'
            '&clienttype=0&desc=1&dir=${_iBoxQueryEncoded(dir)}&is_from_web=true'
            '&num=100&order=other&page=1&sekey=${_iBoxQueryEncoded(randskForList)}'
            '&shareid=${_queryEncoded(shareid)}&showempty=0'
            '&uk=${_queryEncoded(shareUk)}&view_mode=1&web=1';
        final Map<String, Object?>? dirJson =
            await requestShareList(dirUrl, includeAccountCookie: true);
        if (dirJson != null) {
          final Map<String, Object?> root =
              _asMap(dirJson['data']) ?? dirJson;
          final Object? rawList = root['list'];
          if (rawList is List) {
            final List<Map<String, Object?>> items = rawList
                .whereType<Map<Object?, Object?>>()
                .map((Map<Object?, Object?> m) => m.cast<String, Object?>())
                .toList();
            files.addAll(_parsePlayableFiles(items));
            dirsToLoad.addAll(items
                .where(_isDirectory)
                .map((Map<String, Object?> i) => _asString(i['path']) ?? '')
                .where((String p) => p.isNotEmpty));
          }
        }
      }
    }

    if (shareid.isEmpty || shareUk.isEmpty) {
      throw const BaiduIBoxException('百度 iBox 路链未拿到 shareid/uk');
    }
    if (files.isEmpty) {
      throw BaiduIBoxException('百度 iBox share/list 未返回文件列表：$lastListError');
    }

    final BaiduShareMeta meta = BaiduShareMeta(
      shareid: shareid,
      shareUk: shareUk,
      bdstoken: bdstoken,
      surl: surl,
      cookie: iBoxCookie,
      files: files,
      randsk: randskForList,
    );
    await _storeContext(contextKey, meta);
    return meta;
  }

  // ─────────────── 转存链 + DLNA 取链（C2 主链）───────────────

  /// 取用户态 bdstoken（对齐 iOS `baiduFetchUserBdstokenLocal`，WebView 回退属 C3）。
  ///
  /// 私域接口（api/create / filemanager / api/list）必须用登录态 bdstoken；
  /// 分享页 yunData 里的 bdstoken 会被百度判越权（errno=-6）。
  Future<String> fetchUserBdstoken({required String cookie}) async {
    final _Resp tpl = await _request(
      'https://pan.baidu.com/api/gettemplatevariable'
      '?clienttype=0&app_id=250528&web=1'
      '&fields=${Uri.encodeComponent('["bdstoken","token","uk","isdocuser","servertime"]')}',
      headers: <String, String>{
        'Cookie': cookie,
        'User-Agent': webUA,
        'Referer': 'https://pan.baidu.com/disk/main',
      },
      timeout: 12,
    );
    final Map<String, Object?>? json = _decodeMap(tpl.text);
    if (json != null) {
      final String token = _deepString(json, <String>{'bdstoken'});
      if (token.isNotEmpty) return token;
    }
    // 回退：直接抓 disk/main 页面里的用户态 bdstoken。
    final _Resp page = await _request(
      'https://pan.baidu.com/disk/main',
      headers: <String, String>{'Cookie': cookie, 'User-Agent': webUA},
      timeout: 12,
    );
    return extractBdstokenFromHTML(page.text) ?? '';
  }

  /// `/vbox` 转存目录是否可列举（对齐 iOS `baiduCanListTransferDir`）。
  Future<bool> canListTransferDir({
    required String cookie,
    required String bdstoken,
    String referer = 'https://pan.baidu.com/disk/main',
  }) async {
    final _Resp r = await _request(
      'https://pan.baidu.com/api/list?dir=${_queryEncoded(transferDir)}'
      '&order=time&desc=1&num=1&page=1&bdstoken=$bdstoken'
      '&channel=chunlei&web=1&app_id=250528&clienttype=0',
      headers: <String, String>{
        'Cookie': cookie,
        'User-Agent': webUA,
        'Referer': referer,
      },
      timeout: 12,
    );
    final Map<String, Object?>? json = _decodeMap(r.text);
    if (json == null) return false;
    return (_asInt(json['errno']) ?? 0) == 0;
  }

  /// 确保 `/vbox` 转存目录存在（对齐 iOS `baiduEnsureVboxFolderLocal`，WebView 回退属 C3）。
  Future<void> ensureTransferDir({
    required String cookie,
    required String bdstoken,
    String referer = 'https://pan.baidu.com/disk/main',
  }) async {
    if (await canListTransferDir(
      cookie: cookie,
      bdstoken: bdstoken,
      referer: referer,
    )) {
      return;
    }
    String lastResponse = '';
    // ① api/create（严格对齐 iBox 抓包：size=0、method=post，block_list 的 [] 也需编码）
    final _Resp create = await _request(
      'https://pan.baidu.com/api/create?a=commit&bdstoken=$bdstoken'
      '&channel=chunlei&web=1&app_id=250528&clienttype=0',
      method: 'POST',
      headers: <String, String>{
        'Cookie': cookie,
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': webUA,
        'Referer': referer,
        'Origin': 'https://pan.baidu.com',
        'X-Requested-With': 'XMLHttpRequest',
      },
      body: 'path=${_queryEncoded(transferDir)}&size=0&isdir=1'
          '&block_list=${_queryEncoded('[]')}&method=post',
      timeout: 12,
    );
    lastResponse = _preview(create.text);
    final int createErrno = _asInt(_decodeMap(create.text)?['errno']) ?? -1;
    if (createErrno != 0 && createErrno != -8) {
      // ② filemanager create 兜底（对齐 iOS `baiduCreateFolderByFileManager`）。
      final _Resp fm = await _request(
        'https://pan.baidu.com/api/filemanager?opera=create&bdstoken=$bdstoken'
        '&channel=chunlei&web=1&app_id=250528&clienttype=0',
        method: 'POST',
        headers: <String, String>{
          'Cookie': cookie,
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': webUA,
          'Referer': referer,
          'Origin': 'https://pan.baidu.com',
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: 'path=${_queryEncoded(transferDir)}&isdir=1'
            '&block_list=${_queryEncoded('[]')}',
        timeout: 12,
      );
      lastResponse = _preview(fm.text);
    }
    if (await canListTransferDir(
      cookie: cookie,
      bdstoken: bdstoken,
      referer: referer,
    )) {
      return;
    }
    throw BaiduIBoxException('百度 $transferDir 转存目录创建失败：$lastResponse');
  }

  /// 在 `/vbox` 检索已转存文件路径（对齐 iOS `baiduFindExistingVboxPath`）。
  Future<String?> findExistingVboxPath({
    required String fileName,
    required String cookie,
  }) async {
    final _Resp r = await _request(
      'https://pan.baidu.com/api/list?bdstoken=&channel=chunlei&web=1'
      '&app_id=250528&clienttype=0',
      method: 'POST',
      headers: <String, String>{
        'Cookie': cookie,
        'User-Agent': webUA,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'dir=${_queryEncoded(transferDir)}&order=time&desc=1&num=200&page=1',
      timeout: 12,
    );
    final Map<String, Object?>? json = _decodeMap(r.text);
    if (json == null) return null;
    if ((_asInt(json['errno']) ?? 0) != 0) return null;
    return _matchedVboxPath(json, fileName);
  }

  /// 转存落盘确认（对齐 iOS `baiduWaitForTransferredPath`）。
  Future<String> waitForTransferredPath({
    required String fileName,
    required String cookie,
    String? preferredPath,
  }) async {
    if (preferredPath != null && preferredPath.isNotEmpty) return preferredPath;
    final String normalized = _lastPathSegment(fileName);
    for (int attempt = 1; attempt <= transferWaitAttempts; attempt++) {
      if (attempt > 1) {
        final int factor = attempt < 4 ? attempt : 4;
        await Future<void>.delayed(Duration(milliseconds: 650 * factor));
      }
      final String? path =
          await findExistingVboxPath(fileName: normalized, cookie: cookie);
      if (path != null) return path;
    }
    throw BaiduIBoxException('百度转存任务未确认落盘：$transferDir/$normalized');
  }

  /// `share/transfer` 转存单文件（对齐 iOS `baiduTransferFileOnDevice`，WebView 回退属 C3）。
  Future<String> transferFile({
    required String shareUrl,
    required String shareid,
    required String shareUk,
    required String bdstoken,
    required String? randsk,
    required String fsId,
    required String fileName,
    required String cookie,
    required String accountCookie,
    required String referer,
  }) async {
    final String transferCookie =
        await refreshTransferSekey(
          shareUrl: shareUrl,
          accountCookie: accountCookie,
          existingCookie: cookie,
        ) ??
            cookie;
    // sekey 优先 Cookie 里的 BDCLND 原始值（通常已是百分号编码，不能二次编码）。
    final String rawSekey =
        cookieValue(transferCookie, 'BDCLND') ?? randsk ?? '';
    final List<String> query = <String>[
      'shareid=${queryEncodeStrict(shareid)}',
      'from=${queryEncodeStrict(shareUk)}',
      'channel=chunlei',
      'web=1',
      'app_id=250528',
      'clienttype=0',
      'bdstoken=${queryEncodeStrict(bdstoken)}',
    ];
    if (rawSekey.isNotEmpty) {
      final String encodedSekey =
          rawSekey.contains('%') ? rawSekey : queryEncodeStrict(rawSekey);
      query.add('sekey=$encodedSekey');
    }
    final _Resp r = await _request(
      'https://pan.baidu.com/share/transfer?${query.join('&')}',
      method: 'POST',
      headers: <String, String>{
        'Cookie': transferCookie,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': referer,
        'Origin': 'https://pan.baidu.com',
        'X-Requested-With': 'XMLHttpRequest',
        'User-Agent': webUA,
      },
      body: 'fsidlist=${_queryEncoded('[$fsId]')}'
          '&path=${_queryEncoded(transferDir)}&async=1&ondup=newcopy',
      timeout: 25,
    );
    final Map<String, Object?>? json = _decodeMap(r.text);
    if (r.status != 200 || json == null) {
      throw BaiduIBoxException('百度本机转存 HTTP ${r.status}');
    }
    final int errno = _asInt(json['errno']) ?? -1;
    if (errno != 0) {
      throw BaiduIBoxException(
        '百度本机转存失败：${errorMessage(errno, _asString(json['errmsg']) ?? _asString(json['show_msg']))}',
      );
    }
    final Object? list = _asMap(json['extra'])?['list'];
    if (list is List && list.isNotEmpty) {
      final String to = _asString(_asMap(list.first)?['to']) ?? '';
      if (to.isNotEmpty) return to;
    }
    return waitForTransferredPath(
      fileName: _lastPathSegment(fileName),
      cookie: accountCookie,
    );
  }

  /// 账号态 verify 刷新转存 sekey（对齐 iOS `baiduRefreshTransferSekey`）。
  ///
  /// `share/list` 可用匿名分享态验证，但 `share/transfer` 属账号转存动作：百度会
  /// 校验 BDCLND/sekey 是否绑定当前账号会话，否则返回 errno=200025。
  Future<String?> refreshTransferSekey({
    required String shareUrl,
    required String accountCookie,
    required String existingCookie,
  }) async {
    final String? pwd = extractPwd(shareUrl);
    final String? surl = extractSurl(shareUrl);
    if (pwd == null || pwd.isEmpty || surl == null || surl.isEmpty) return null;
    final String short = shortSurl(surl);
    final _Resp r = await _request(
      'https://pan.baidu.com/share/verify?t=${DateTime.now().millisecondsSinceEpoch}'
      '&surl=$short&channel=chunlei&web=1&app_id=250528&bdstoken=&clienttype=0',
      method: 'POST',
      headers: <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        'Cookie': accountCookie,
        'User-Agent': webUA,
        'Origin': 'https://pan.baidu.com',
        'Referer': 'https://pan.baidu.com/s/1$short',
        'Accept': '*/*',
        'Accept-Language': 'zh-Hans-001;q=1.0',
      },
      body: 'pwd=${queryEncodeStrict(pwd)}&vcode=&vcode_str=&channel=chunlei'
          '&web=1&app_id=250528&clienttype=0&bdstoken=',
      timeout: 18,
    );
    final Map<String, Object?>? json = _decodeMap(r.text);
    if (json == null || (_asInt(json['errno']) ?? -1) != 0) return null;
    String merged = mergeCookieStrings(
      <String>[existingCookie, accountCookie, ...r.setCookies],
    );
    final String? rawRandsk = _asString(json['randsk']);
    if (rawRandsk != null && rawRandsk.isNotEmpty) {
      final String decoded = Uri.decodeComponent(rawRandsk);
      merged = mergeCookieStrings(
        <String>[merged, 'BDCLND=$rawRandsk; randsk=$decoded'],
      );
    }
    return merged;
  }

  /// `api/mediainfo` DLNA 取链（对齐 iOS `baiduGetDLNADlinkOnDevice`）。
  Future<BaiduPlayResult> getDLNADlink({
    required String filePath,
    required String cookie,
    String source = 'local-mediainfo',
  }) async {
    final _Resp r = await _request(
      'https://pan.baidu.com/api/mediainfo?clienttype=80&origin=dlna',
      method: 'POST',
      headers: <String, String>{
        'Cookie': cookie,
        'User-Agent': pcsUserAgent,
        'Accept': '*/*',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'path=${_queryEncoded(filePath)}&type=M3U8_FLV_264_480',
      timeout: 20,
    );
    if (r.status != 200) {
      throw BaiduIBoxException('百度 DLNA HTTP ${r.status}');
    }
    final Map<String, Object?>? json = _decodeMap(r.text);
    if (json == null) {
      throw const BaiduIBoxException('百度 DLNA 返回非 JSON');
    }
    final Map<String, Object?>? info = _asMap(json['info']);
    final String dlink = _asString(info?['dlink']) ??
        _asString(json['dlink']) ??
        _asString(json['url']) ??
        '';
    if (dlink.isNotEmpty) return _playResult(dlink, cookie, source);
    final int errno = _asInt(json['errno']) ?? -1;
    throw BaiduIBoxException(
      '百度 DLNA 未返回 dlink：${errorMessage(errno, _asString(json['errmsg']) ?? _asString(json['show_msg']) ?? _asString(json['msg']))}',
    );
  }

  /// `locatedownload` 原画取链（对齐 iOS `baiduGetLocatedownloadOnDevice`）。
  Future<BaiduPlayResult> getLocatedownload({
    required String filePath,
    required String cookie,
    String source = 'local-locatedownload',
    bool enableFastestNode = false,
  }) async {
    final String url =
        'https://d.pcs.baidu.com/rest/2.0/pcs/file?app_id=250528'
        '&method=locatedownload&check_blue=1&path=${_queryEncoded(filePath)}';
    final _Resp r = await _request(
      url,
      headers: <String, String>{
        'Cookie': cookie,
        'User-Agent': pcsUserAgent,
        'Referer': 'https://pan.baidu.com/',
        'Origin': 'https://pan.baidu.com',
        'Accept': '*/*',
      },
      timeout: 20,
    );
    // 302 已由传输层跟随：CDN 落点即最终地址。
    if ((r.status == 200 || r.status == 206) &&
        r.finalUrl.isNotEmpty &&
        r.finalUrl != url &&
        !r.finalUrl.contains('d.pcs.baidu.com/rest/2.0/pcs/file')) {
      return _playResult(r.finalUrl, cookie, source);
    }
    final String location = r.headers['location'] ?? '';
    if (r.status >= 300 && r.status < 400 && location.isNotEmpty) {
      return _playResult(location, cookie, source);
    }
    if (r.status != 200) {
      throw BaiduIBoxException('百度本机取链 HTTP ${r.status}');
    }
    final Map<String, Object?>? json = _decodeMap(r.text);
    if (json == null) {
      throw const BaiduIBoxException('百度本机取链返回非 JSON');
    }
    final int errno = _asInt(json['errno']) ?? 0;
    if (errno != 0) {
      throw BaiduIBoxException(
        '百度本机取链失败：${errorMessage(errno, _asString(json['errmsg']) ?? _asString(json['show_msg']) ?? _asString(json['msg']))}',
      );
    }
    final Object? rawUrls = json['urls'];
    final List<String> all = rawUrls is List
        ? rawUrls
            .whereType<Map<Object?, Object?>>()
            .map((Map<Object?, Object?> m) => _asString(m['url']) ?? '')
            .where((String u) => u.isNotEmpty)
            .toList()
        : const <String>[];
    final String located = all.isNotEmpty
        ? all.first
        : (_asString(json['url']) ?? _asString(json['dlink']) ?? '');
    if (located.isEmpty) {
      throw const BaiduIBoxException('百度本机取链未返回播放地址');
    }
    if (enableFastestNode && all.length > 1) {
      final _BaiduNodeSpeed? fastest = await _findFastestNode(all, cookie);
      if (fastest != null && fastest.url != located) {
        return _playResult(fastest.url, cookie, '$source-fastest');
      }
    }
    return _playResult(located, cookie, source);
  }

  /// 分享链接 + fsId → 播放地址（对齐 iOS `resolveBaiduPlayURLViaMainRoute` 主链）。
  ///
  /// `wap/init → verify → 分享页/yunData → gettemplatevariable → share/list →
  /// api/create → api/list → share/transfer → api/list → locatedownload(→mediainfo)`。
  /// 不含 iOS 的 WebView 回退（C3）与 1 小时后清理调度（空间管理项）。
  Future<BaiduPlayResult> resolvePlayURL({
    required String shareUrl,
    required String bduss,
    required String fsId,
    String pcsCookie = '',
  }) async {
    final ({String cookie, String bduss}) parsed = parseToken(bduss);
    final String webCookie = parsed.cookie;
    final String pcs = normalizePCSCookie(pcsCookie);
    final String accountCookie = mergeCookieStrings(<String>[webCookie, pcs]);
    final String pureCookie = pureAccountCookie(accountCookie);
    final BaiduShareMeta context = await extractShareMeta(
      shareUrl: shareUrl,
      cookie: webCookie,
      returnAll: true,
    );
    // 分享页解析与 bdstoken 获取可并行（对齐 iOS [优化2]）。
    final String userBdstoken = await fetchUserBdstoken(cookie: pureCookie);
    if (userBdstoken.isEmpty) {
      throw const BaiduIBoxException(
        '百度登录态正常，但未取得用户态 bdstoken，无法创建 vbox 转存目录',
      );
    }
    final BaiduFileItem? selected = _selectFile(context.files, fsId);
    if (selected == null) {
      throw const BaiduIBoxException('主路链未找到可播放视频');
    }
    final String mergedCookie =
        mergeCookieStrings(<String>[context.cookie, accountCookie]);
    if (mergedCookie.isEmpty) {
      throw const BaiduIBoxException('主路链缺少百度 Cookie');
    }
    await ensureTransferDir(
      cookie: pureCookie,
      bdstoken: userBdstoken,
      referer: 'https://pan.baidu.com/disk/main',
    );
    final String? existing = await findExistingVboxPath(
      fileName: selected.name,
      cookie: pureCookie,
    );
    final String filePath;
    final String sourcePrefix;
    if (existing != null) {
      filePath = existing;
      sourcePrefix = 'main-existing';
    } else {
      filePath = await transferFile(
        shareUrl: shareUrl,
        shareid: context.shareid,
        shareUk: context.shareUk,
        bdstoken: userBdstoken,
        randsk: context.randsk,
        fsId: selected.fsId,
        fileName: selected.name,
        cookie: mergedCookie,
        accountCookie: pureCookie,
        referer: shareUrl,
      );
      sourcePrefix = 'main-transfer';
    }
    try {
      return await getLocatedownload(
        filePath: filePath,
        cookie: mergedCookie,
        source: '$sourcePrefix-locatedownload',
        enableFastestNode: true,
      );
    } on BaiduIBoxException {
      // locatedownload 失败 → mediainfo dlink 兜底（对齐 iOS）。
      return getDLNADlink(
        filePath: filePath,
        cookie: mergedCookie,
        source: '$sourcePrefix-mediainfo-fallback',
      );
    }
  }

  // ─────────────── 内部：HTTP ───────────────

  Future<_Resp> _request(
    String url, {
    String method = 'GET',
    Map<String, String> headers = const <String, String>{},
    String? body,
    int timeout = 15,
  }) async {
    final SpiderTransportResponse res = await _transport.send(
      SpiderTransportRequest(
        method: method,
        url: Uri.parse(url),
        headers: headers,
        body: body,
        timeout: Duration(seconds: timeout),
      ),
    );
    final String text = utf8.decode(res.bodyBytes, allowMalformed: true);
    return _Resp(
      text: text,
      setCookies: res.setCookies,
      status: res.status,
      headers: res.headers,
      finalUrl: res.finalUrl.isEmpty ? url : res.finalUrl,
    );
  }

  // ─────────────── 内部：解析 ───────────────

  /// 从 HTML 抓 yunData（shareid/uk/bdstoken/FILEINFO）（对齐 iOS `applyYunDataHTML`）。
  void _applyYunDataHtml(String html, List<BaiduFileItem> files) {
    String first(List<String> patterns) {
      for (final String p in patterns) {
        final RegExpMatch? m = RegExp(p, caseSensitive: false).firstMatch(html);
        if (m != null && m.groupCount >= 1 && m.group(1) != null) {
          return m.group(1)!;
        }
      }
      return '';
    }

    final String fileinfo = first(<String>[
      r'yunData\.FILEINFO\s*=\s*(\[[\s\S]*?\]);',
    ]);
    if (fileinfo.isEmpty) return;
    final Object? decoded = _tryDecode(fileinfo);
    if (decoded is! List) return;
    final List<Map<String, Object?>> items = decoded
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) => m.cast<String, Object?>())
        .toList();
    final List<BaiduFileItem> parsed = _parsePlayableFiles(items);
    if (files.isEmpty && parsed.isNotEmpty) files.addAll(parsed);
  }

  /// 解析可播放文件（过滤目录与非视频）（对齐 iOS `parsePlayableFiles`）。
  List<BaiduFileItem> _parsePlayableFiles(List<Map<String, Object?>> rawList) {
    final List<BaiduFileItem> out = <BaiduFileItem>[];
    for (final Map<String, Object?> item in rawList) {
      if (_isDirectory(item)) continue;
      final String fsId = _asString(item['fs_id']) ??
          _asString(item['fsId']) ??
          '';
      final String name = _asString(item['server_filename']) ??
          _asString(item['file_name']) ??
          _asString(item['name']) ??
          '';
      if (fsId.isEmpty) continue;
      final BaiduFileItem f =
          BaiduFileItem(fsId: fsId, name: name.isEmpty ? '未知文件' : name);
      if (f.isPlayableVideo) out.add(f);
    }
    return out;
  }

  bool _isDirectory(Map<String, Object?> item) {
    final String v = _asString(item['isdir']) ?? '';
    return v == '1' || v.toLowerCase() == 'true';
  }

  static String _queryEncoded(String value) {
    // 对齐 iOS `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)`：
    // 空格 → %20（非 `+`），保留 `:/?&=` 等 query 常用字符。
    const String allowed = "-._~!$&'()*+,;=:@/?";
    final StringBuffer sb = StringBuffer();
    for (final int rune in value.runes) {
      final String ch = String.fromCharCode(rune);
      final bool keep =
          RegExp(r'[A-Za-z0-9]').hasMatch(ch) || allowed.contains(ch);
      sb.write(keep ? ch : Uri.encodeComponent(ch));
    }
    return sb.toString();
  }

  /// iBox 保留 `/` 的查询编码（对齐 iOS `iBoxQueryEncoded(keepSlash: true)`）。
  static String _iBoxQueryEncoded(String value) {
    const String keep = '/';
    final StringBuffer sb = StringBuffer();
    for (final int rune in value.runes) {
      final String ch = String.fromCharCode(rune);
      final bool ok = RegExp(r'[A-Za-z0-9\-_.~]').hasMatch(ch) ||
          (keep.contains(ch) && ch.isNotEmpty);
      sb.write(ok ? ch : Uri.encodeComponent(ch));
    }
    return sb.toString();
  }

  /// 分享态 Cookie 过滤（对齐 iOS `cookieForShareList`）。
  static String _cookieForShareList(
    String cookie, {
    required bool includeAccount,
  }) {
    final Set<String> drop = <String>{
      'stoken', 'stoken_bfess', 'ptoken', 'ptoken_bfess',
      'passid', 'ubi_bfess', 'randsk',
    };
    if (!includeAccount) {
      drop.addAll(<String>['bduss', 'bduss_bfess']);
    }
    return cookie
        .split(';')
        .map((String p) => p.trim())
        .where((String part) {
          final int eq = part.indexOf('=');
          if (eq <= 0) return false;
          final String name = part.substring(0, eq).toLowerCase();
          return !drop.contains(name);
        })
        .join('; ');
  }

  static String _deepString(Object? value, Set<String> keys) {
    final Object? normalized = _parseJsonStringIfNeeded(value);
    if (normalized is Map) {
      for (final MapEntry<Object?, Object?> e in normalized.entries) {
        if (keys.contains('${e.key}'.toLowerCase())) {
          final String direct = _asString(e.value) ?? '';
          if (direct.isNotEmpty) return direct;
        }
      }
      for (final Object? raw in normalized.values) {
        final String found = _deepString(raw, keys);
        if (found.isNotEmpty) return found;
      }
    } else if (normalized is List) {
      for (final Object? raw in normalized) {
        final String found = _deepString(raw, keys);
        if (found.isNotEmpty) return found;
      }
    }
    return '';
  }

  /// 深层找文件列表（对齐 iOS `deepFiles`）。
  List<BaiduFileItem> _deepFiles(Object? value) {
    final Object? normalized = _parseJsonStringIfNeeded(value);
    if (normalized is Map) {
      for (final String key in <String>[
        'list', 'file_list', 'records', 'filelist', 'result', 'data', 'info',
      ]) {
        final Object? raw = normalized[key];
        if (raw is List) {
          final List<BaiduFileItem> parsed = _parsePlayableFiles(
            raw
                .whereType<Map<Object?, Object?>>()
                .map((Map<Object?, Object?> m) => m.cast<String, Object?>())
                .toList(),
          );
          if (parsed.isNotEmpty) return parsed;
        }
        if (raw != null) {
          final List<BaiduFileItem> nested = _deepFiles(raw);
          if (nested.isNotEmpty) return nested;
        }
      }
      for (final Object? raw in normalized.values) {
        final List<BaiduFileItem> found = _deepFiles(raw);
        if (found.isNotEmpty) return found;
      }
    } else if (normalized is List) {
      final List<BaiduFileItem> parsed = _parsePlayableFiles(
        normalized
            .whereType<Map<Object?, Object?>>()
            .map((Map<Object?, Object?> m) => m.cast<String, Object?>())
            .toList(),
      );
      if (parsed.isNotEmpty) return parsed;
      for (final Object? raw in normalized) {
        final List<BaiduFileItem> found = _deepFiles(raw);
        if (found.isNotEmpty) return found;
      }
    }
    return const <BaiduFileItem>[];
  }

  static Object? _parseJsonStringIfNeeded(Object? value) {
    if (value is! String) return value;
    final String trimmed = value.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return value;
    return _tryDecode(trimmed) ?? value;
  }

  // ─────────────── 内部：C2 助手 ───────────────

  /// 组装播放结果（对齐 iOS `baiduPlayResult`）。
  BaiduPlayResult _playResult(String url, String cookie, String source) =>
      BaiduPlayResult(
        url: url,
        headers: <String, String>{
          'Cookie': cookie,
          'User-Agent': pcsUserAgent,
          'Referer': 'https://pan.baidu.com/',
          'Origin': 'https://pan.baidu.com',
        },
        source: source,
      );

  /// 路径末段文件名。
  static String _lastPathSegment(String path) {
    final List<String> parts = path.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  /// 去扩展名（对齐 iOS `deletingPathExtension`）。
  static String _deletePathExtension(String name) {
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// 取扩展名（对齐 iOS `pathExtension`）。
  static String _pathExtension(String name) {
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot + 1) : '';
  }

  /// 在 `/vbox` 列表中匹配目标文件（对齐 iOS `baiduFindExistingVboxPath.matchedPath`）。
  static String? _matchedVboxPath(
    Map<String, Object?> json,
    String fileName,
  ) {
    final Map<String, Object?> root = _asMap(json['data']) ?? json;
    final Object? rawList =
        root['list'] ?? root['file_list'] ?? root['records'];
    if (rawList is! List) return null;
    final String normalizedTarget = _lastPathSegment(fileName);
    final String targetBase = _deletePathExtension(normalizedTarget);
    final String targetExt = _pathExtension(normalizedTarget);
    for (final Object? raw in rawList) {
      final Map<String, Object?>? item = _asMap(raw);
      if (item == null) continue;
      final String name = _asString(item['server_filename']) ??
          _asString(item['filename']) ??
          _asString(item['name']) ??
          '';
      final String nameBase = _deletePathExtension(name);
      final String nameExt = _pathExtension(name);
      if (name == normalizedTarget ||
          (targetBase.isNotEmpty &&
              nameBase.startsWith(targetBase) &&
              (targetExt.isEmpty || nameExt == targetExt))) {
        final String path = _asString(item['path']) ?? '';
        return path.isNotEmpty ? path : '$transferDir/$normalizedTarget';
      }
    }
    return null;
  }

  /// 选集：优先 fsId 命中的可播放文件，否则首个可播放文件（对齐 iOS 主路链判定）。
  static BaiduFileItem? _selectFile(List<BaiduFileItem> files, String fsId) {
    for (final BaiduFileItem f in files) {
      if (f.fsId.trim() == fsId.trim() && f.isPlayableVideo) return f;
    }
    for (final BaiduFileItem f in files) {
      if (f.isPlayableVideo) return f;
    }
    return null;
  }

  /// 多 CDN 节点 HEAD 测速选优（对齐 iOS `baiduFindFastestNode`，单节点 3s 超时）。
  Future<_BaiduNodeSpeed?> _findFastestNode(
    List<String> urls,
    String cookie,
  ) async {
    final List<_BaiduNodeSpeed?> results = await Future.wait(
      <Future<_BaiduNodeSpeed?>>[
        for (final String url in urls) _probeNode(url, cookie),
      ],
    );
    _BaiduNodeSpeed? best;
    for (final _BaiduNodeSpeed? r in results) {
      if (r == null) continue;
      if (best == null || r.rttMs < best.rttMs) best = r;
    }
    return best;
  }

  Future<_BaiduNodeSpeed?> _probeNode(String url, String cookie) async {
    final DateTime start = DateTime.now();
    try {
      final _Resp r = await _request(
        url,
        method: 'HEAD',
        headers: <String, String>{
          'Cookie': cookie,
          'User-Agent': pcsUserAgent,
          'Referer': 'https://pan.baidu.com/',
        },
        timeout: 3,
      );
      final bool ok = r.status == 200 ||
          r.status == 206 ||
          (r.status >= 300 && r.status < 400);
      if (!ok) return null;
      return _BaiduNodeSpeed(
        url: url,
        rttMs: DateTime.now().difference(start).inMilliseconds,
      );
    } catch (_) {
      return null;
    }
  }

  // ─────────────── 内部：缓存 ───────────────

  String _shareContextKey(String shareUrl, String cookie) =>
      '$shareUrl|${crypto.sha256.convert(utf8.encode(cookie)).toString().substring(0, 16)}';

  Future<BaiduShareMeta?> _cachedContext(String key) async {
    try {
      final PrefsManager p = _prefs ?? PrefsManager.instance;
      final String raw = await p.getString(shareContextCacheKey);
      if (raw.isEmpty) return null;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Object? entry = decoded[key];
      if (entry is! Map) return null;
      final Map<String, Object?> e = entry.cast<String, Object?>();
      final int exp = (e['expiresAt'] as num?)?.toInt() ?? 0;
      if (exp <= DateTime.now().millisecondsSinceEpoch) return null;
      final Object? filesRaw = e['files'];
      final List<BaiduFileItem> files = filesRaw is List
          ? filesRaw
              .whereType<Map<Object?, Object?>>()
              .map((Map<Object?, Object?> m) => BaiduFileItem(
                    fsId: _asString(m['fsId']) ?? '',
                    name: _asString(m['name']) ?? '',
                  ))
              .where((BaiduFileItem f) => f.fsId.isNotEmpty)
              .toList(growable: false)
          : const <BaiduFileItem>[];
      if (files.isEmpty) return null;
      return BaiduShareMeta(
        shareid: _asString(e['shareid']) ?? '',
        shareUk: _asString(e['shareUk']) ?? '',
        bdstoken: _asString(e['bdstoken']) ?? '',
        surl: _asString(e['surl']) ?? '',
        cookie: _asString(e['cookie']) ?? '',
        files: files,
        randsk: _asString(e['randsk']) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeContext(String key, BaiduShareMeta meta) async {
    try {
      final PrefsManager p = _prefs ?? PrefsManager.instance;
      final String raw = await p.getString(shareContextCacheKey);
      Map<String, Object?> cache = <String, Object?>{};
      if (raw.isNotEmpty) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) cache = decoded.cast<String, Object?>();
      }
      final int now = DateTime.now().millisecondsSinceEpoch;
      cache[key] = <String, Object?>{
        'shareid': meta.shareid,
        'shareUk': meta.shareUk,
        'bdstoken': meta.bdstoken,
        'surl': meta.surl,
        'cookie': meta.cookie,
        'randsk': meta.randsk,
        'files': meta.files
            .map((BaiduFileItem f) =>
                <String, Object?>{'fsId': f.fsId, 'name': f.name})
            .toList(growable: false),
        'createdAt': now,
        'expiresAt': now + shareContextTtl.inMilliseconds,
      };
      // 过期裁剪。
      cache.removeWhere((String _, Object? v) {
        final Map<String, Object?>? m =
            v is Map ? v.cast<String, Object?>() : null;
        return ((m?['expiresAt'] as num?)?.toInt() ?? 0) <= now;
      });
      await p.set(shareContextCacheKey, jsonEncode(cache));
    } catch (_) {
      // 落盘失败不阻断（下次重抓）。
    }
  }

  // ─────────────── JSON 助手 ───────────────

  static Map<String, Object?>? _decodeMap(String body) {
    final Object? d = _tryDecode(body);
    return d is Map ? d.cast<String, Object?>() : null;
  }

  static Object? _tryDecode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
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

  static String _preview(String text) =>
      text.length <= 200 ? text : text.substring(0, 200);
}

/// CDN 节点测速结果（对齐 iOS `BaiduNodeSpeedResult`）。
class _BaiduNodeSpeed {
  const _BaiduNodeSpeed({required this.url, required this.rttMs});

  final String url;
  final int rttMs;
}

/// 轻量响应（正文 + Set-Cookie + 状态/头/最终 URL）。
class _Resp {
  const _Resp({
    required this.text,
    required this.setCookies,
    this.status = 200,
    this.headers = const <String, String>{},
    this.finalUrl = '',
  });

  final String text;
  final List<String> setCookies;
  final int status;
  final Map<String, String> headers;
  final String finalUrl;
}

/// 便捷：去掉 surl 前导 1（顶层可读别名）。
String shortSurlOf(String surl) => BaiduIBoxClient.shortSurl(surl);