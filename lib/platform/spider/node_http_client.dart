/// 平台层：Node 桥 HTTP 客户端抽象 + 本机实现。
///
/// 对齐 iOS 常驻 Node 进程协议（`127.0.0.1:58080 /spider/`，lx-music 为 58083）。
/// 抽象注入点：测试注入 fake，避免真实端口依赖。
library;

import 'dart:convert';
import 'dart:io';

/// Node 桥 HTTP 客户端（可注入）。
abstract class NodeHttpClient {
  /// POST [path]，请求体 [body]（ABI JSON），返回响应体字符串。
  Future<String> postJson(String path, String body);

  /// 释放连接资源。
  Future<void> close();
}

/// 本机常驻 Node 进程客户端（`127.0.0.1:<port>`）。
class LocalNodeHttpClient implements NodeHttpClient {
  /// [port] 默认 58080（Node 源）；lx-music 用 58083。
  LocalNodeHttpClient({required this.port, this.timeout = const Duration(seconds: 15)});

  final int port;
  final Duration timeout;
  final HttpClient _client = HttpClient();

  @override
  Future<String> postJson(String path, String body) async {
    final HttpClientRequest req = await _client
        .postUrl(Uri.parse('http://127.0.0.1:$port$path'))
        .timeout(timeout);
    req.headers.contentType = ContentType.json;
    req.write(body);
    final HttpClientResponse res = await req.close().timeout(timeout);
    return res.transform(utf8.decoder).join();
  }

  @override
  Future<void> close() async => _client.close(force: true);
}
