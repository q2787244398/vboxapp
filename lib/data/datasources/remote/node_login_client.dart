/// 数据层：Node 常驻系统登录协议客户端（批次 F · F-P16）。
///
/// 对齐 iOS `NodeLoginViews.swift` 的 `NodeLoginAPIClient.request`：
/// 统一 POST/PUT/GET 到 `http://127.0.0.1:58080/website/api/...`，非 2xx / 非 JSON 抛错。
/// 覆盖：通用扫码（115/夸克Node/百度Node/UCNode）、光鸭/139/迅雷短信、
/// 123/189 账号、蜗牛图形验证码（预留）。
///
/// 协议调用经 [NodeLoginTransport] 抽象注入（UI / 测试不依赖真实端口）；
/// 缺省 [LocalNodeLoginTransport] 走 `127.0.0.1:58080`（对齐 iOS
/// `NodeRuntimeManager.shared.baseURL`），3 次退避重试。
library;

import 'dart:convert';
import 'dart:io';

import '../../../domain/entities/cloud/node_login.dart';

/// Node 登录接口传输接缝（可注入）。
abstract interface class NodeLoginTransport {
  /// 发起 [method] 请求到 [path]，返回解析后的 JSON 对象。
  ///
  /// 失败（Node 未就绪 / 非 2xx / 非 JSON）抛 [NodeLoginException]。
  Future<Map<String, dynamic>> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  });
}

/// 缺省接缝：Node 常驻系统未接入（对齐 iOS `nodeNotReady`）。
class UnavailableNodeLoginTransport implements NodeLoginTransport {
  /// 构造。
  const UnavailableNodeLoginTransport();

  @override
  Future<Map<String, dynamic>> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async =>
      throw const NodeLoginException('Node 常驻系统未就绪');
}

/// 本机常驻 Node 进程客户端（`127.0.0.1:<port>`，默认 58080）。
class LocalNodeLoginTransport implements NodeLoginTransport {
  /// 构造（[port] 默认 58080；[timeout] 单次超时；[attempts] 最大尝试次数）。
  LocalNodeLoginTransport({
    this.port = 58080,
    this.timeout = const Duration(seconds: 20),
    this.attempts = 3,
  });

  /// Node 端口。
  final int port;

  /// 单次请求超时。
  final Duration timeout;

  /// 最大尝试次数。
  final int attempts;

  final HttpClient _client = HttpClient();

  @override
  Future<Map<String, dynamic>> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    NodeLoginException last = const NodeLoginException('未知错误');
    for (int attempt = 1; attempt <= attempts; attempt++) {
      try {
        final HttpClientRequest req = await _client
            .openUrl(method, Uri.parse('http://127.0.0.1:$port$path'))
            .timeout(timeout);
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body ?? <String, dynamic>{}));
        final HttpClientResponse res = await req.close().timeout(timeout);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw NodeLoginException('HTTP ${res.statusCode}');
        }
        final String text = await res.transform(utf8.decoder).join();
        final Object? decoded =
            text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
        if (decoded is! Map) {
          throw const NodeLoginException('响应解析失败');
        }
        final Map<String, dynamic> json = <String, dynamic>{
          for (final MapEntry<Object?, Object?> e in decoded.entries)
            e.key.toString(): e.value,
        };
        // Node 侧统一 {code,msg}；code != 0 视为业务失败（terminal 例外，由调用方处理）。
        final Object? code = json['code'];
        final bool ok = code is int ? code == 0 : '${code ?? ''}' == '0';
        if (!ok && json['terminal'] != true) {
          throw NodeLoginException('${json['msg'] ?? 'Node 返回错误 code=$code'}');
        }
        return json;
      } catch (e) {
        last = e is NodeLoginException ? e : NodeLoginException('$e');
        if (attempt < attempts) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }
    throw last;
  }

  /// 释放连接资源。
  void close() => _client.close(force: true);
}

/// Node 登录协议异常（文案对齐 iOS `NodeLoginError`）。
class NodeLoginException implements Exception {
  /// 构造。
  const NodeLoginException(this.message);

  /// 面向用户的错误文案。
  final String message;

  @override
  String toString() => message;
}

/// 扫码轮询结果（对齐 iOS `poll` 的三要素）。
typedef NodeLoginPoll = ({String status, bool terminal, String msg});

/// Node 登录协议客户端。
class NodeLoginClient {
  /// 构造（[transport] 可注入；缺省本机 Node 客户端）。
  NodeLoginClient({NodeLoginTransport? transport})
      : _transport = transport ?? LocalNodeLoginTransport();

  final NodeLoginTransport _transport;

  // ─────────────── 通用扫码 ───────────────

  /// 发起扫码：返回 `(taskId, qrDataUrl)`（对齐 iOS `regenerate`）。
  Future<({String taskId, String qrDataUrl})> startQr(String provider) async {
    final Map<String, dynamic> json = await _transport.requestJson(
      'POST',
      NodeLoginPaths.qrStart,
      body: <String, dynamic>{'provider': provider},
    );
    final String taskId = '${json['taskId'] ?? ''}';
    if (taskId.isEmpty) {
      throw const NodeLoginException('二维码生成失败：缺少 taskId');
    }
    return (taskId: taskId, qrDataUrl: '${json['qrImage'] ?? ''}');
  }

  /// 轮询一次扫码状态（对齐 iOS `poll`）。
  Future<NodeLoginPoll> pollQr({
    required String provider,
    required String taskId,
  }) async {
    final Map<String, dynamic> json = await _transport.requestJson(
      'POST',
      NodeLoginPaths.qrPoll,
      body: <String, dynamic>{'provider': provider, 'taskId': taskId},
    );
    return (
      status: '${json['status'] ?? 'waiting'}',
      terminal: json['terminal'] == true,
      msg: '${json['msg'] ?? ''}',
    );
  }

  /// 取消扫码任务（幂等；失败不抛，对齐 iOS `cancelTask`）。
  Future<void> cancelQr(String taskId) async {
    try {
      await _transport.requestJson(
        'POST',
        NodeLoginPaths.qrCancel,
        body: <String, dynamic>{'taskId': taskId},
      );
    } catch (_) {
      // 取消为幂等操作，失败不冒泡。
    }
  }

  // ─────────────── 光鸭短信 ───────────────

  /// 光鸭发送短信（对齐 iOS `sendSms`）：返回 `taskId`。
  Future<String> guangyaSendSms(String phone) async {
    final Map<String, dynamic> json = await _transport.requestJson(
      'POST',
      NodeLoginPaths.guangyaSmsSend,
      body: <String, dynamic>{'phone': phone},
    );
    return '${json['taskId'] ?? ''}';
  }

  /// 光鸭短信登录（对齐 iOS `loginSms`）。
  Future<void> guangyaLoginSms({
    required String taskId,
    required String code,
  }) =>
      _transport.requestJson(
        'POST',
        NodeLoginPaths.guangyaSmsLogin,
        body: <String, dynamic>{'taskId': taskId, 'code': code},
      );

  // ─────────────── 139 短信 ───────────────

  /// 139 发送短信（对齐 iOS `sendSms`）：返回 `loginHeaders` / `captchaUrl`。
  Future<({Map<String, String> headers, String captchaUrl, String msg})>
      new139SendSms(String phone) async {
    final Map<String, dynamic> json = await _transport.requestJson(
      'POST',
      NodeLoginPaths.new139SmsSend,
      body: <String, dynamic>{'phone': phone},
    );
    final Object? raw = json['loginHeaders'];
    final Map<String, String> headers = raw is Map
        ? <String, String>{
            for (final MapEntry<Object?, Object?> e in raw.entries)
              e.key.toString(): '${e.value}',
          }
        : const <String, String>{};
    return (
      headers: headers,
      captchaUrl: '${json['captchaUrl'] ?? ''}',
      msg: '${json['msg'] ?? ''}',
    );
  }

  /// 139 短信登录（对齐 iOS `loginSms`）。
  Future<void> new139Login({
    required String phone,
    required String code,
    required Map<String, String> headers,
  }) =>
      _transport.requestJson(
        'POST',
        NodeLoginPaths.new139Login,
        body: <String, dynamic>{
          'phone': phone,
          'code': code,
          'headers': headers,
        },
      );

  // ─────────────── 迅雷短信 ───────────────

  /// 迅雷发送短信（对齐 iOS `sendSms`；Node 不返回 taskId）。
  Future<void> thunderSendSms(String mobile) => _transport.requestJson(
        'POST',
        NodeLoginPaths.thunderSmsSend,
        body: <String, dynamic>{'mobile': mobile},
      );

  /// 迅雷短信登录（对齐 iOS `loginSms`）。
  Future<void> thunderLoginSms(String code) => _transport.requestJson(
        'POST',
        NodeLoginPaths.thunderSmsLogin,
        body: <String, dynamic>{'code': code},
      );

  // ─────────────── 123 账号 ───────────────

  /// 123 账号登录（对齐 iOS `submit`）。
  Future<void> pan123Account({
    required String account,
    required String password,
  }) =>
      _transport.requestJson(
        'PUT',
        NodeLoginPaths.pan123Account,
        body: <String, dynamic>{'account': account, 'password': password},
      );

  // ─────────────── 189 账号 / 短信 ───────────────

  /// 189 账号登录（对齐 iOS `submit`）：返回是否需短信二次校验。
  Future<({bool sms, String msg})> pan189Account({
    required String account,
    required String password,
  }) async {
    final Map<String, dynamic> json = await _transport.requestJson(
      'PUT',
      NodeLoginPaths.pan189Account,
      body: <String, dynamic>{'account': account, 'password': password},
    );
    return (sms: json['sms'] == true, msg: '${json['msg'] ?? ''}');
  }

  /// 189 短信登录（对齐 iOS `submit` 的 `needSms` 分支）。
  Future<void> pan189SmsLogin(String code) => _transport.requestJson(
        'POST',
        NodeLoginPaths.pan189SmsLogin,
        body: <String, dynamic>{'code': code},
      );

  // ─────────────── 蜗牛账号（图形验证码，预留）───────────────

  /// 蜗牛获取图形验证码（对齐 iOS `fetchVerify`）。
  Future<({String taskId, String image})> woniuVerify() async {
    final Map<String, dynamic> json =
        await _transport.requestJson('GET', NodeLoginPaths.woniuVerify);
    final Object? data = json['data'];
    final Map<String, dynamic> raw =
        data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
    final String taskId = '${raw['taskId'] ?? ''}';
    final String image = '${raw['image'] ?? ''}';
    if (taskId.isEmpty || image.isEmpty) {
      throw const NodeLoginException('验证码获取失败：响应缺少 taskId/image');
    }
    return (taskId: taskId, image: image);
  }

  /// 蜗牛账号登录（对齐 iOS `submit`）。
  Future<void> woniuLogin({
    required String account,
    required String password,
    required String verify,
    required String taskId,
  }) =>
      _transport.requestJson(
        'PUT',
        NodeLoginPaths.woniuLogin,
        body: <String, dynamic>{
          'account': account,
          'password': password,
          'verify': verify,
          'taskId': taskId,
        },
      );
}