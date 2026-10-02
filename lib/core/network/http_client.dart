/// 核心层：轻量 HTTP 客户端。
///
/// 职责（对齐 iOS `Services/*Service.swift` 的通用请求约定）：
/// - 统一 UA / 头合并
/// - 超时 + 退避重试（5xx 与网络层错误重试，4xx 不重试）
/// - 响应体按契约 §4.2 探测链解码（见 `http_body_decoder.dart`）
/// - 网络层异常归一为 `NetworkException`
///
/// 不做的事：cookie 管理、代理、证书绕过 —— 属平台层/蜘蛛桥接层职责。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import '../errors/exceptions.dart';
import '../utils/logger.dart';
import 'http_body_decoder.dart';
import 'network_info.dart';

/// 已解码的 HTTP 响应。
class HttpClientResponse {
  /// 构造。
  const HttpClientResponse({
    required this.uri,
    required this.statusCode,
    required this.headers,
    required this.text,
    required this.rawBytes,
    required this.usedBase64Fallback,
  });

  /// 请求地址。
  final Uri uri;

  /// 状态码。
  final int statusCode;

  /// 响应头（键已小写）。
  final Map<String, String> headers;

  /// 按契约 §4.2 解码后的文本。
  final String text;

  /// 原始字节。
  final Uint8List rawBytes;

  /// 是否走了 base64 兜底。
  final bool usedBase64Fallback;

  /// 2xx。
  bool get isOk => statusCode >= 200 && statusCode < 300;

  /// 3xx。
  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  /// 字节长度。
  int get byteLength => rawBytes.length;

  @override
  String toString() => 'HttpClientResponse($statusCode, ${rawBytes.length}B, $uri)';
}

/// HTTP 客户端。
class HttpClient {
  /// 构造（[inner] 便于测试注入 MockClient）。
  HttpClient({
    http.Client? inner,
    this.networkInfo,
    this.maxRetries = NetConstants.maxRetries,
    this.retryBaseDelay = NetConstants.retryBaseDelay,
    this.receiveTimeout = NetConstants.receiveTimeout,
    this.userAgent = NetConstants.defaultUserAgent,
  }) : _inner = inner ?? http.Client();

  final http.Client _inner;

  /// 网络可达性（A2；为 null 时不做主动判断，等价于 AlwaysOnline）。
  final NetworkInfo? networkInfo;

  /// 日志标签。
  static const String logTag = 'network';

  /// 最大重试次数。
  final int maxRetries;

  /// 重试基础退避。
  final Duration retryBaseDelay;

  /// 单次请求读超时。
  final Duration receiveTimeout;

  /// 默认 UA。
  final String userAgent;

  /// GET。
  Future<HttpClientResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    String? metaCharsetOverride,
  }) =>
      send('GET', uri, headers: headers, metaCharsetOverride: metaCharsetOverride);

  /// POST 表单。
  Future<HttpClientResponse> postForm(
    Uri uri,
    Map<String, String> form, {
    Map<String, String>? headers,
    String? metaCharsetOverride,
  }) =>
      send(
        'POST',
        uri,
        headers: headers,
        form: form,
        metaCharsetOverride: metaCharsetOverride,
      );

  /// POST JSON（原始 JSON 字符串 body，供 MDTV 等加密协议使用）。
  Future<HttpClientResponse> postJson(
    Uri uri, {
    Object? json,
    Map<String, String>? headers,
    String? metaCharsetOverride,
  }) =>
      send(
        'POST',
        uri,
        headers: headers,
        body: json == null ? null : jsonEncode(json),
        metaCharsetOverride: metaCharsetOverride,
      );

  /// 通用发送（带重试）。
  Future<HttpClientResponse> send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Map<String, String>? form,
    String? body,
    String? metaCharsetOverride,
  }) async {
    // A2：离线短路 —— 探针明确报离线时不进入重试循环，直接失败，避免无谓等待。
    final NetworkInfo? info = networkInfo;
    if (info != null && !await info.isConnected) {
      AppLog.warn(logTag, '设备当前离线，跳过请求：$method $uri');
      throw NetworkException(
        '当前无网络：$uri',
        code: ErrorCode.networkUnreachable,
      );
    }

    Object? lastError;
    AppLog.debug(logTag, '$method $uri');
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final http.Response res =
            await _dispatch(method, uri, headers, form, body)
                .timeout(receiveTimeout);
        if (res.statusCode >= 500 && attempt < maxRetries) {
          AppLog.warn(
            logTag,
            'HTTP ${res.statusCode}，重试 ${attempt + 1}/$maxRetries：$method $uri',
          );
          await Future<void>.delayed(backoff(attempt));
          continue;
        }
        AppLog.debug(logTag, 'HTTP ${res.statusCode}：$method $uri');
        return _decode(uri, res, metaCharsetOverride);
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
      AppLog.warn(
        logTag,
        '请求异常（第 ${attempt + 1}/${maxRetries + 1} 次）：$method $uri',
        error: lastError,
      );
      if (attempt < maxRetries) {
        await Future<void>.delayed(backoff(attempt));
      }
    }
    AppLog.error(logTag, '请求最终失败：$method $uri', error: lastError);
    throw NetworkException(
      '请求失败：$uri',
      code: ErrorCode.networkUnreachable,
      cause: lastError,
    );
  }

  /// 释放底层连接。
  void close() => _inner.close();

  /// 第 [attempt] 次重试的等待时长（指数退避）。
  Duration backoff(int attempt) => retryBaseDelay * (1 << attempt);

  Future<http.Response> _dispatch(
    String method,
    Uri uri,
    Map<String, String>? headers,
    Map<String, String>? form,
    String? body,
  ) {
    final Map<String, String> h = <String, String>{
      'user-agent': userAgent,
      'accept': '*/*',
      ...?headers,
    };
    switch (method.toUpperCase()) {
      case 'POST':
        if (body != null) {
          h['content-type'] = 'application/json; charset=utf-8';
          return _inner.post(uri, headers: h, body: body);
        }
        h['content-type'] = 'application/x-www-form-urlencoded; charset=utf-8';
        return _inner.post(uri, headers: h, body: form ?? const <String, String>{});
      case 'GET':
      default:
        return _inner.get(uri, headers: h);
    }
  }

  HttpClientResponse _decode(
    Uri uri,
    http.Response res,
    String? metaCharsetOverride,
  ) {
    final Uint8List bytes = res.bodyBytes;
    final (String text, bool usedBase64) = decodeResponseBody(
      bytes,
      contentTypeCharset: res.headers['content-type'],
      metaCharsetOverride: metaCharsetOverride,
    );
    return HttpClientResponse(
      uri: uri,
      statusCode: res.statusCode,
      headers: res.headers,
      text: text,
      rawBytes: bytes,
      usedBase64Fallback: usedBase64,
    );
  }
}
