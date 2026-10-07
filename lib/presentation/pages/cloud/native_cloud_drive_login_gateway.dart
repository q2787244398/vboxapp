/// 网盘登录网关 · 原生扫码实现（批次 F · F-05 余项）。
///
/// 承接 F-02 定义的 [CloudDriveLoginGateway] 接缝，补齐 iOS
/// `NativeCloudQRLoginView`（`SettingsViews.swift:4391`）中**不经 Node 常驻系统**
/// 的三条原生扫码链：
/// - **UC 网盘**：`api.open.uc.cn/cas/ajax/getTokenForQrcodeLogin`
///   → 本地生成二维码（`su.uc.cn` 授权链接）→ `getServiceTicketByQrcodeToken`
///   → `drive.uc.cn/account/mobileinfo` 换取 `__pus/kps/__uid` Cookie
///   （对齐 iOS `ucCreateQrToken` / `ucPollQrStatus` / `ucExchangeServiceTicket`）；
/// - **百度网盘**：`passport.baidu.com/v2/api/getqrcode`（图片二维码）
///   → `passport.baidu.com/channel/unicast` 轮询 → `qrbdusslogin` 逐跳跟随
///   重定向收集 `BDUSS/STOKEN` Cookie（对齐 iOS `baiduCreateQrToken` /
///   `baiduPollQrStatus` / `baiduExchangeQrLogin`）；
/// - **夸克网盘**：`uop.quark.cn/cas/ajax/getTokenForQrcodeLogin`
///   → 本地生成二维码（`su.quark.cn` 授权链接）→ `getServiceTicketByQrcodeToken`
///   → `pan.quark.cn/account/info` 换取 `__kps/__pus/__uid` Cookie
///   （对齐 iOS `quarkCreateQrToken` / `quarkPollQrStatus` /
///   `quarkExchangeServiceTicket`）。
///
/// 成功后统一写入契约安全存储 `cloud_drive_credentials_v1`（`authType=qr`），
/// 授权中心据此展示「已获取」。
///
/// 未覆盖：阿里（走 PG/extscreen，[AliyunPgLoginGateway]）与 Node 托管盘
/// （[NodeCloudDriveLoginGateway]）。
library;

import 'dart:convert';
import 'dart:math' as math;

import '../../../data/datasources/local/cloud_drive_credential_store.dart';
import '../../../data/datasources/local/prefs_manager.dart';
import '../../../domain/entities/cloud/cloud_drive.dart';
import '../../../domain/entities/cloud/cloud_drive_login.dart';
import '../../../platform/spider/spider_http_bridge.dart';
import 'login_gateway.dart';

/// UC 扫码任务暂存（跨 start/poll 复用 token 与轮询 client_id）。
class _UcQrTask {
  const _UcQrTask({required this.token, required this.pollClientId});

  final String token;
  final String pollClientId;
}

/// 百度扫码任务暂存（`sign` 为交换兜底参数）。
class _BaiduQrTask {
  const _BaiduQrTask({
    required this.sign,
    required this.channelId,
    required this.qrURL,
  });

  final String sign;
  final String channelId;
  final String qrURL;
}

/// 夸克扫码任务暂存。
class _QuarkQrTask {
  const _QuarkQrTask({required this.token, required this.pollClientId});

  final String token;
  final String pollClientId;
}

/// 原生扫码登录网关（UC / 百度 / 夸克）。
class NativeCloudDriveLoginGateway implements CloudDriveLoginGateway {
  /// 构造（[bridge] / [credentialStore] 供测试注入）。
  NativeCloudDriveLoginGateway({
    SpiderHttpBridge? bridge,
    CloudDriveCredentialStore? credentialStore,
  })  : _bridge = bridge ?? SpiderHttpBridge(),
        _store = credentialStore ??
            CloudDriveCredentialStore(PrefsManager.instance);

  final SpiderHttpBridge _bridge;
  final CloudDriveCredentialStore _store;

  /// 原生扫码覆盖的网盘（对齐 iOS 原生档；不含阿里 / Node 托管盘）。
  static const Set<CloudDriveType> nativeTypes = <CloudDriveType>{
    CloudDriveType.uc,
    CloudDriveType.baidu,
    CloudDriveType.quark,
  };

  /// 该网关是否覆盖给定网盘 / 方式。
  static bool supports(CloudDriveType type, CloudDriveLoginMode mode) =>
      mode == CloudDriveLoginMode.nativeQr && nativeTypes.contains(type);

  // ─────────────── iOS 契约常量 ───────────────

  static const String _ucWebClientId = '381';
  static const String _ucUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) uc-cloud-drive/1.8.5 '
      'Chrome/100.0.4896.160 Electron/18.3.5.16-b62cf9c50d Safari/537.36 '
      'Channel/ucpan_other_ch';
  static const String _ucMobileUserAgent =
      'Mozilla/5.0 (Linux; Android 12; HD1900 Build/SKQ1.211113.001; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
      'Chrome/97.0.4692.98 Mobile Safari/537.36';
  static const String _baiduUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const String _quarkUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/94.0.4606.54 Safari/537.36';
  static const String _quarkQrClientId = '386';
  static const String _quarkPollClientId = '532';

  final Map<String, _UcQrTask> _ucTasks = <String, _UcQrTask>{};
  final Map<String, _BaiduQrTask> _baiduTasks = <String, _BaiduQrTask>{};
  final Map<String, _QuarkQrTask> _quarkTasks = <String, _QuarkQrTask>{};

  // ─────────────── 扫码入口 ───────────────

  @override
  Future<CloudDriveQrTask> startQrLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
    String? providerOverride,
  }) async {
    if (!supports(type, mode)) {
      throw const CloudDriveLoginException('该网盘不支持原生扫码登录');
    }
    switch (type) {
      case CloudDriveType.uc:
        return _ucStart();
      case CloudDriveType.baidu:
        return _baiduStart();
      case CloudDriveType.quark:
        return _quarkStart();
      default:
        throw CloudDriveLoginException('${type.displayName} 原生扫码尚未接入');
    }
  }

  @override
  Future<CloudDriveLoginPhase> pollQrLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
    required String taskId,
    String? providerOverride,
  }) async {
    if (!supports(type, mode)) {
      throw const CloudDriveLoginException('该网盘不支持原生扫码登录');
    }
    switch (type) {
      case CloudDriveType.uc:
        return _ucPoll(taskId);
      case CloudDriveType.baidu:
        return _baiduPoll(taskId);
      case CloudDriveType.quark:
        return _quarkPoll(taskId);
      default:
        throw CloudDriveLoginException('${type.displayName} 原生扫码尚未接入');
    }
  }

  @override
  Future<void> cancelQrLogin(String taskId) async {
    _ucTasks.remove(taskId);
    _baiduTasks.remove(taskId);
    _quarkTasks.remove(taskId);
  }

  // ─────────────── UC ───────────────

  Future<CloudDriveQrTask> _ucStart() async {
    final int ts = _nowMs();
    final Uri url = Uri.parse('https://api.open.uc.cn/cas/ajax/getTokenForQrcodeLogin')
        .replace(queryParameters: <String, String>{'__dt': '2951', '__t': '$ts'});
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(
        method: 'POST',
        headers: <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          'Origin': 'https://broccoli.uc.cn',
          'Referer': 'https://broccoli.uc.cn/',
          'User-Agent': _ucUserAgent,
          'Accept': '*/*',
        },
        data: 'client_id=$_ucWebClientId&request_id=$ts&v=1.2',
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    String token = _pickString(json, <String>['token', 'qrcode_token']);
    if (token.isEmpty) token = _nestedString(json, <String>['data', 'members', 'token']) ?? '';
    if (token.isEmpty) token = _nestedString(json, <String>['data', 'token']) ?? '';
    if (token.isEmpty) token = _nestedString(json, <String>['result', 'token']) ?? '';
    if (token.isEmpty) {
      throw CloudDriveLoginException(_apiMessage(json, 'UC 未返回二维码 token'));
    }
    final String taskId = 'uc_${_randomHex(16)}';
    _ucTasks[taskId] = _UcQrTask(token: token, pollClientId: _ucWebClientId);
    return (
      taskId: taskId,
      qrDataUrl: '$kQrDataContentPrefix${_ucQrPayload(token, _ucWebClientId)}',
    );
  }

  Future<CloudDriveLoginPhase> _ucPoll(String taskId) async {
    final _UcQrTask? task = _ucTasks[taskId];
    if (task == null) {
      throw const CloudDriveLoginException('扫码任务已失效，请重新生成二维码');
    }
    final int ts = _nowMs();
    final Uri url =
        Uri.parse('https://api.open.uc.cn/cas/ajax/getServiceTicketByQrcodeToken')
            .replace(queryParameters: <String, String>{'__dt': '10314', '__t': '$ts'});
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(
        method: 'POST',
        headers: <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          'Origin': 'https://broccoli.uc.cn',
          'Referer': 'https://broccoli.uc.cn/',
          'User-Agent': _ucUserAgent,
          'Accept': '*/*',
        },
        data: 'client_id=${task.pollClientId}&request_id=$ts'
            '&token=${task.token}&v=1.2',
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    final String ticket = _nestedString(json, <String>['data', 'members', 'service_ticket']) ??
        _nestedString(json, <String>['data', 'service_ticket']) ??
        _nestedString(json, <String>['result', 'service_ticket']) ??
        _pickString(json, <String>['service_ticket', 'ticket']);
    if (ticket.isNotEmpty) {
      await _ucExchange(ticket);
      _ucTasks.remove(taskId);
      return CloudDriveLoginPhase.success;
    }
    final int status = _pickInt(json, <String>['status', 'code']) ??
        _nestedInt(json, <String>['data', 'members', 'status']) ??
        _nestedInt(json, <String>['data', 'status']) ??
        -1;
    if (const <int>{50004002, 50004003, 50004004, 50004005, 50004006, 50004007}
        .contains(status)) {
      _ucTasks.remove(taskId);
      throw const CloudDriveLoginException('二维码已过期，请重试');
    }
    if (status == 50004000) return CloudDriveLoginPhase.scanned;
    return CloudDriveLoginPhase.waitingScan;
  }

  Future<void> _ucExchange(String serviceTicket) async {
    final Uri url = Uri.parse('https://drive.uc.cn/account/mobileinfo')
        .replace(queryParameters: <String, String>{
      'pr': 'UCBrowser',
      'fr': 'h5',
      '__t': '${_nowMs()}',
      'st': serviceTicket,
    });
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(
        headers: <String, String>{
          'Origin': 'https://drive.uc.cn',
          'Referer': 'https://drive.uc.cn/',
          'User-Agent': _ucMobileUserAgent,
          'Accept-Language': 'zh-Hans-001;q=1.0',
          'Accept': '*/*',
        },
      ),
    );
    final Map<String, String> cookies = _cookiesFromHeaders(res.headers);
    final Map<String, Object?>? data = _asMap(_decodeMap(res.content)?['data']);
    _putCredential(cookies, '__pus', data?['__pus']);
    _putCredential(cookies, 'kps', data?['kps']);
    _putCredential(cookies, '__uid', data?['uid']);
    final String cookie = joinCookies(cookies);
    final bool ok = cookie.contains('__pus=') ||
        cookie.contains('__kps=') ||
        cookie.contains('__uid=');
    if (!ok) {
      throw const CloudDriveLoginException('UC Cookie 缺少必须字段，登录可能无效');
    }
    await _persist(
      CloudDriveType.uc,
      cookie: cookie,
      statusMessage: 'UC 扫码登录成功',
    );
  }

  /// UC 二维码内容（对齐 iOS `ucQRCodePayload`：`su.uc.cn` 授权链接）。
  static String _ucQrPayload(String token, String clientId) =>
      Uri.parse('https://su.uc.cn/1_n0ZCv').replace(queryParameters: <String, String>{
        'uc_param_str': 'frpfbive',
        'fr': 'iphone',
        'pf': '44',
        'bi': '997',
        've': '18.9.8.2995',
        'token': token,
        'client_id': clientId,
        'uc_biz_str': 'S:custom|C:titlebar_fix',
      }).toString();

  // ─────────────── 百度 ───────────────

  Future<CloudDriveQrTask> _baiduStart() async {
    final int ts = _nowMs();
    final Uri url = Uri.parse('https://passport.baidu.com/v2/api/getqrcode')
        .replace(queryParameters: <String, String>{
      'lp': 'pc',
      'qrloginfrom': 'pc',
      'gid': _randomHex(32),
      'apiver': 'v3',
      'tt': '$ts',
    });
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(
        headers: <String, String>{
          'User-Agent': _baiduUserAgent,
          'Accept': 'application/json, text/plain, */*',
        },
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    String sign = _pickString(json, <String>['sign']);
    if (sign.isEmpty) sign = _nestedString(json, <String>['data', 'sign']) ?? '';
    String channelId = _pickString(json, <String>['channel_id']);
    if (channelId.isEmpty) channelId = _nestedString(json, <String>['data', 'channel_id']) ?? sign;
    String imgurl = _pickString(json, <String>['imgurl']);
    if (imgurl.isEmpty) imgurl = _nestedString(json, <String>['data', 'imgurl']) ?? '';
    if (sign.isEmpty || imgurl.isEmpty) {
      throw CloudDriveLoginException(_apiMessage(json, '百度未返回二维码 sign/imgurl'));
    }
    final String qrURL = imgurl.startsWith('http')
        ? imgurl
        : 'https://${imgurl.replaceAll(RegExp(r'^/+'), '')}';
    final String taskId = 'baidu_${_randomHex(16)}';
    _baiduTasks[taskId] =
        _BaiduQrTask(sign: sign, channelId: channelId, qrURL: qrURL);
    // 百度返回的是**图片地址**（非文本），表现层按远程图片渲染。
    return (taskId: taskId, qrDataUrl: qrURL);
  }

  Future<CloudDriveLoginPhase> _baiduPoll(String taskId) async {
    final _BaiduQrTask? task = _baiduTasks[taskId];
    if (task == null) {
      throw const CloudDriveLoginException('扫码任务已失效，请重新生成二维码');
    }
    final Uri url = Uri.parse('https://passport.baidu.com/channel/unicast')
        .replace(queryParameters: <String, String>{
      'channel_id': task.channelId,
      'tpl': 'netdisk',
      'apiver': 'v3',
      'tt': '${_nowMs()}',
    });
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(
        headers: <String, String>{
          'User-Agent': _baiduUserAgent,
          'Accept': 'application/json, text/plain, */*',
        },
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    final int errno = _pickInt(json, <String>['errno']) ?? -1;
    if (errno == 1 || errno == 2) return CloudDriveLoginPhase.waitingScan;
    if (errno == 0) {
      Map<String, Object?> payload = json ?? const <String, Object?>{};
      final Object? raw = json?['channel_v'];
      if (raw is String) {
        final Map<String, Object?>? nested = _decodeMap(raw);
        if (nested != null) payload = nested;
      }
      final int status = _pickInt(payload, <String>['status']) ?? -1;
      String bdussURL = _pickString(payload, <String>['bduss']);
      if (bdussURL.isEmpty) bdussURL = _pickString(payload, <String>['v']);
      if (status == 2 || bdussURL.isNotEmpty) {
        await _baiduExchange(task, bdussURL.isEmpty ? null : bdussURL);
        _baiduTasks.remove(taskId);
        return CloudDriveLoginPhase.success;
      }
      if (status == 0 || status == 1) return CloudDriveLoginPhase.scanned;
      return CloudDriveLoginPhase.waitingScan;
    }
    if (errno == 3 || errno == 4) {
      _baiduTasks.remove(taskId);
      throw const CloudDriveLoginException('二维码已过期，请重试');
    }
    final String msg = _pickString(json, <String>['errmsg']);
    throw CloudDriveLoginException(
      msg.isNotEmpty ? msg : '百度轮询异常 errno=$errno',
    );
  }

  Future<void> _baiduExchange(_BaiduQrTask task, String? bdussURL) async {
    final String bdussParam = _normalizeBaiduBduss(bdussURL) ?? task.sign;
    final Uri url = Uri.parse('https://passport.baidu.com/v3/login/main/qrbdusslogin')
        .replace(queryParameters: <String, String>{
      'v': '${_nowMs()}',
      'bduss': bdussParam,
      'u': 'https://pan.baidu.com/disk/main',
      'loginVersion': 'v4',
      'qrcode': '1',
      'tpl': 'netdisk',
    });
    final Map<String, String> cookies = await _collectFollowingRedirects(
      url.toString(),
      headers: <String, String>{
        'User-Agent': _baiduUserAgent,
        'Referer': 'https://pan.baidu.com/',
      },
    );
    final String cookie = joinCookies(cookies);
    if (!_isBaiduAccountCookie(cookie)) {
      throw const CloudDriveLoginException('百度扫码未返回完整 BDUSS/STOKEN');
    }
    await _persist(
      CloudDriveType.baidu,
      cookie: cookie,
      statusMessage: '百度扫码登录成功，已保存 BDUSS/STOKEN',
      extra: <String, String>{'cookie_mode': 'BDUSS_STOKEN'},
    );
  }

  /// 百度 `bduss` 参数归一（对齐 iOS `normalizeBaiduQrBDUSSParam`）。
  static String? _normalizeBaiduBduss(String? raw) {
    if (raw == null) return null;
    String value = raw.trim();
    if (value.isEmpty) return null;
    try {
      value = Uri.decodeComponent(value);
    } catch (_) {
      // 保持原值。
    }
    final Uri? uri = Uri.tryParse(value);
    if (uri != null && uri.hasQuery) {
      final String? b =
          uri.queryParameters['bduss'] ?? uri.queryParameters['BDUSS'];
      if (b != null && b.isNotEmpty) return b;
    }
    final RegExpMatch? m = RegExp(r'(?:^|[?&])bduss=([^&\s]+)', caseSensitive: false)
        .firstMatch(value);
    return m?.group(1) ?? value;
  }

  /// 逐跳跟随 3xx 并收集各跳 `Set-Cookie`（百度登录态主要落在重定向跳）。
  Future<Map<String, String>> _collectFollowingRedirects(
    String url, {
    required Map<String, String> headers,
    int maxHops = 5,
  }) async {
    final Map<String, String> cookies = <String, String>{};
    String current = url;
    for (int hop = 0; hop <= maxHops; hop++) {
      final SpiderHttpResult res = await _bridge.request(
        current,
        options: SpiderHttpOptions(
          headers: <String, String>{
            ...headers,
            if (cookies.isNotEmpty) 'Cookie': joinCookies(cookies),
          },
          followRedirects: false,
        ),
      );
      cookies.addAll(_cookiesFromHeaders(res.headers));
      if (res.status < 300 || res.status >= 400) break;
      final String location = res.headers['location'] ?? '';
      if (location.isEmpty) break;
      current = Uri.parse(current).resolve(location).toString();
    }
    return cookies;
  }

  static bool _isBaiduAccountCookie(String cookie) =>
      cookie.contains('BDUSS=') && cookie.contains('STOKEN=');

  // ─────────────── 夸克 ───────────────

  Future<CloudDriveQrTask> _quarkStart() async {
    final Uri url = Uri.parse('https://uop.quark.cn/cas/ajax/getTokenForQrcodeLogin')
        .replace(queryParameters: <String, String>{
      'pr': 'ucpro',
      'fr': 'pc',
      'sys': 'darwin',
      'client_id': _quarkQrClientId,
      'v': '1.2',
      'request_id': _randomUuid(),
    });
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(
        headers: <String, String>{
          'Origin': 'https://pan.quark.cn',
          'Referer': 'https://pan.quark.cn/',
          'User-Agent': _quarkUserAgent,
          'Accept': '*/*',
        },
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    final int status = _pickInt(json, <String>['status']) ?? -1;
    final String token = _nestedString(json, <String>['data', 'members', 'token']) ?? '';
    if (status != 2000000 || token.isEmpty) {
      throw CloudDriveLoginException(_apiMessage(json, '夸克扫码 token 接口异常'));
    }
    final String taskId = 'quark_${_randomHex(16)}';
    _quarkTasks[taskId] =
        _QuarkQrTask(token: token, pollClientId: _quarkPollClientId);
    return (
      taskId: taskId,
      qrDataUrl:
          '$kQrDataContentPrefix${_quarkQrPayload(token, _quarkPollClientId)}',
    );
  }

  Future<CloudDriveLoginPhase> _quarkPoll(String taskId) async {
    final _QuarkQrTask? task = _quarkTasks[taskId];
    if (task == null) {
      throw const CloudDriveLoginException('扫码任务已失效，请重新生成二维码');
    }
    final Uri url =
        Uri.parse('https://uop.quark.cn/cas/ajax/getServiceTicketByQrcodeToken')
            .replace(queryParameters: <String, String>{
      'client_id': task.pollClientId,
      'v': '1.2',
      'request_id': _randomUuid(),
      'token': task.token,
    });
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(
        headers: <String, String>{
          'Origin': 'https://pan.quark.cn',
          'Referer': 'https://pan.quark.cn/',
          'User-Agent': _quarkUserAgent,
          'Accept': '*/*',
        },
      ),
    );
    final Map<String, Object?>? json = _decodeMap(res.content);
    final int status = _pickInt(json, <String>['status']) ?? -1;
    if (status == 2000000) {
      final String ticket =
          _nestedString(json, <String>['data', 'members', 'service_ticket']) ?? '';
      if (ticket.isEmpty) {
        throw const CloudDriveLoginException('夸克未返回 service_ticket');
      }
      await _quarkExchange(ticket);
      _quarkTasks.remove(taskId);
      return CloudDriveLoginPhase.success;
    }
    if (status == 50004001) return CloudDriveLoginPhase.waitingScan;
    if (status == 50004002 || status == 50004003 || status == 50004004) {
      _quarkTasks.remove(taskId);
      throw const CloudDriveLoginException('二维码已过期，请重试');
    }
    final String msg = _pickString(json, <String>['message']);
    throw CloudDriveLoginException(
      msg.isNotEmpty ? '夸克扫码失败：$msg' : '夸克扫码状态异常（$status）',
    );
  }

  Future<void> _quarkExchange(String serviceTicket) async {
    final Uri url = Uri.parse('https://pan.quark.cn/account/info')
        .replace(queryParameters: <String, String>{
      'st': serviceTicket,
      'fr': 'pc',
      'platform': 'pc',
    });
    final SpiderHttpResult res = await _bridge.request(
      url.toString(),
      options: SpiderHttpOptions(
        headers: <String, String>{
          'Origin': 'https://pan.quark.cn',
          'Referer': 'https://pan.quark.cn/',
          'User-Agent': _quarkUserAgent,
          'Accept': '*/*',
        },
      ),
    );
    final Map<String, String> cookies = _cookiesFromHeaders(res.headers);
    final String cookie = joinCookies(cookies);
    for (final String key in <String>['__kps', '__pus', '__uid']) {
      if (!cookie.contains('$key=')) {
        throw CloudDriveLoginException('夸克未拿到 $key Cookie，可能扫码授权失败');
      }
    }
    final Map<String, Object?>? json = _decodeMap(res.content);
    final Map<String, Object?>? data = _asMap(json?['data']);
    final String nick = _pickString(data, <String>['nickname', 'nick_name']).isNotEmpty
        ? _pickString(data, <String>['nickname', 'nick_name'])
        : _pickString(json, <String>['nickname']);
    await _persist(
      CloudDriveType.quark,
      cookie: cookie,
      statusMessage: '夸克扫码登录成功',
      userName: nick.isEmpty ? null : nick,
    );
  }

  /// 夸克二维码内容（对齐 iOS `quarkQRCodePayload`：`su.quark.cn` 授权链接）。
  static String _quarkQrPayload(String token, String clientId) =>
      Uri.parse('https://su.quark.cn/4_eMHBJ').replace(queryParameters: <String, String>{
        'token': token,
        'client_id': clientId,
        'ssb': 'weblogin',
        'uc_param_str': '',
        'uc_biz_str': 'S:custom|OPT:SAREA@0|OPT:IMMERSIVE@1|OPT:BACK_BTN_STYLE@0',
      }).toString();

  // ─────────────── 落库 ───────────────

  /// 凭据落库（`cloud_drive_credentials_v1`）；失败不阻断「登录成功」展示。
  Future<void> _persist(
    CloudDriveType type, {
    required String cookie,
    required String statusMessage,
    String? userName,
    Map<String, String>? extra,
  }) async {
    try {
      final DateTime now = DateTime.now();
      await _store.save(CloudDriveCredential(
        driveType: type.id,
        authType: CloudDriveAuthType.qr,
        cookie: cookie,
        userName: userName ?? '${type.displayName}扫码账号',
        state: CloudDriveAuthState.valid,
        statusMessage: statusMessage,
        updatedAt: now,
        lastCheckedAt: now,
        extra: extra ?? const <String, String>{},
      ));
    } catch (_) {
      // 凭据回收失败不影响登录态（对齐 iOS 网关容错）。
    }
  }

  // ─────────────── 非扫码档（原生网关不承载）───────────────

  @override
  Future<String> sendSmsCode({
    required CloudDriveType type,
    required String phone,
  }) async =>
      throw const CloudDriveLoginException('该网盘不支持验证码登录');

  @override
  Future<void> submitSmsCode({
    required CloudDriveType type,
    required String taskId,
    required String code,
  }) async =>
      throw const CloudDriveLoginException('该网盘不支持验证码登录');

  @override
  Future<void> submitAccountLogin({
    required CloudDriveType type,
    required CloudDriveLoginMode mode,
    required String account,
    required String password,
    String captchaCode = '',
  }) async =>
      throw const CloudDriveLoginException('该网盘不支持账号密码登录');

  @override
  String? pendingCaptchaUrl(CloudDriveType type) => null;

  @override
  Future<String?> loadAccountCaptcha(CloudDriveType type) async => null;

  // ─────────────── 工具 ───────────────

  /// 从响应头收集 `Set-Cookie`（小写键；值按 `name=value` 提取）。
  static Map<String, String> _cookiesFromHeaders(Map<String, String> headers) {
    final Map<String, String> out = <String, String>{};
    final RegExp re = RegExp(r'([A-Za-z0-9_\-]+)=([^;,]+)');
    for (final MapEntry<String, String> e in headers.entries) {
      if (e.key.toLowerCase() != 'set-cookie') continue;
      for (final RegExpMatch m in re.allMatches(e.value)) {
        final String k = m.group(1) ?? '';
        final String v = (m.group(2) ?? '').trim();
        if (k.isNotEmpty && v.isNotEmpty) out[k] = v;
      }
    }
    return out;
  }

  static void _putCredential(Map<String, String> out, String key, Object? value) {
    if (value is String && value.isNotEmpty) out[key] = value;
    if (value is num) out[key] = '$value';
  }

  /// Cookie 字典 → `a=1; b=2`（对齐 iOS `cookieDict.joined`）。
  static String joinCookies(Map<String, String> cookies) => cookies.entries
      .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
      .join('; ');

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  static String _randomHex(int length) {
    final math.Random rng = math.Random();
    const String hex = '0123456789abcdef';
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < length; i++) {
      sb.write(hex[rng.nextInt(16)]);
    }
    return sb.toString();
  }

  /// 小写 UUID（8-4-4-4-12；对齐 iOS `UUID().uuidString.lowercased()`）。
  static String _randomUuid() {
    final String h = _randomHex(32);
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

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

  /// 一级键取字符串（首个非空命中）。
  static String _pickString(Map<String, Object?>? json, List<String> keys) {
    if (json == null) return '';
    for (final String k in keys) {
      final Object? v = json[k];
      if (v is String && v.isNotEmpty) return v;
      if (v is num) return '$v';
    }
    return '';
  }

  /// 一级键取整数。
  static int? _pickInt(Map<String, Object?>? json, List<String> keys) {
    if (json == null) return null;
    for (final String k in keys) {
      final Object? v = json[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final int? parsed = int.tryParse(v);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  /// 按路径取嵌套字符串（任一层非 Map / 缺键 → null）。
  static String? _nestedString(Map<String, Object?>? json, List<String> path) {
    Object? current = json;
    for (final String k in path) {
      final Map<String, Object?>? m = _asMap(current);
      if (m == null) return null;
      current = m[k];
    }
    return current is String ? current : null;
  }

  /// 按路径取嵌套整数。
  static int? _nestedInt(Map<String, Object?>? json, List<String> path) {
    Object? current = json;
    for (final String k in path) {
      final Map<String, Object?>? m = _asMap(current);
      if (m == null) return null;
      current = m[k];
    }
    if (current is int) return current;
    if (current is num) return current.toInt();
    if (current is String) return int.tryParse(current);
    return null;
  }

  /// 接口错误文案（`message` / `msg` / `error_info`，缺省回退）。
  static String _apiMessage(Map<String, Object?>? json, String fallback) {
    if (json == null) return fallback;
    for (final String k in <String>['message', 'msg', 'error_info', 'errmsg']) {
      final Object? v = json[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return fallback;
  }
}
