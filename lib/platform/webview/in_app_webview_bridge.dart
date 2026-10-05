/// 平台层：内嵌 WebView 桥的 `flutter_inappwebview` 承载实现（批次 F · Web-R1）。
///
/// 实现 [WebViewBridge] 的三项能力（对齐 iOS WKWebView 语义）：
///   · [loadPage]：无头加载页面（`HeadlessInAppWebView`）→ `onLoadStop` 取
///     `document.documentElement.outerHTML` + `CookieManager.getCookies`
///     （**HttpOnly 可读**，这是选 `flutter_inappwebview` 而非 `webview_flutter`
///     的根本原因）；
///   · [request]：在**同源承载页**上下文执行同步 `XMLHttpRequest`（规避 CORS），
///     返回 `status/body/headers`（对齐 iOS `BaiduWebViewBridge.request`）；
///   · [currentCookieString]：`CookieManager.getCookies` 拼串。
///
/// 平台可用性：[isAvailable] 仅在 Android / iOS / macOS 为 true；
/// Windows/Linux 无 `flutter_inappwebview` 实现，返回 false（消费点回退
/// 「系统浏览器 + 粘贴」兜底），不影响构建。
///
/// 说明：本文件按 `flutter_inappwebview` 6.x 稳定 API 编写；因交付沙箱无
/// Flutter/Dart SDK，具体类/方法签名未经本地编译验证，若 CI 报错需按插件
/// 实际签名微调（已登记于方案文档）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'webview_bridge.dart';

/// 基于 `flutter_inappwebview` 的 WebView 桥实现。
class InAppWebViewBridge implements WebViewBridge {
  /// 构造。
  InAppWebViewBridge();

  @override
  bool get isAvailable =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  void _ensureAvailable() {
    if (!isAvailable) {
      throw const WebViewBridgeException('当前平台不支持 WebView 桥（Web-R1）');
    }
  }

  @override
  Future<WebViewPageResult> loadPage({
    required String url,
    String? userAgent,
    Map<String, String> cookies = const <String, String>{},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _ensureAvailable();
    final WebUri uri = WebUri(url);
    final CookieManager cookieManager = CookieManager.instance();
    // 预注入 Cookie：HttpOnly 只能经 CookieManager 写入（不能靠 document.cookie）。
    for (final MapEntry<String, String> e in cookies.entries) {
      await cookieManager.setCookie(
        url: uri,
        name: e.key,
        value: e.value,
      );
    }

    final Completer<WebViewPageResult> completer =
        Completer<WebViewPageResult>();
    final HeadlessInAppWebView headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: uri),
      initialSettings: InAppWebViewSettings(
        userAgent: userAgent,
        javaScriptEnabled: true,
      ),
      onLoadStop: (InAppWebViewController controller, WebUri? loaded) async {
        try {
          final Object? html = await controller.evaluateJavascript(
            source: 'document.documentElement.outerHTML',
          );
          final List<Cookie> cs = await cookieManager.getCookies(url: uri);
          final String cookieStr =
              cs.map((Cookie c) => '${c.name}=${c.value}').join('; ');
          if (!completer.isCompleted) {
            completer.complete((
              html: '${html ?? ''}',
              url: '${loaded ?? uri}',
              cookie: cookieStr,
            ));
          }
        } catch (e) {
          if (!completer.isCompleted) {
            completer.completeError(WebViewBridgeException('页面读取失败：$e'));
          }
        }
      },
      onReceivedError: (
        InAppWebViewController controller,
        WebResourceRequest request,
        WebResourceError error,
      ) {
        if (!completer.isCompleted) {
          completer.completeError(
            WebViewBridgeException('页面加载失败：${error.description}'),
          );
        }
      },
    );
    await headless.run();
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      throw const WebViewBridgeException('页面加载超时');
    } finally {
      await headless.dispose();
    }
  }

  @override
  Future<WebViewXhrResult> request({
    required String url,
    String method = 'GET',
    Map<String, String> headers = const <String, String>{},
    String? body,
    String? hostUrl,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    _ensureAvailable();
    final String host = hostUrl ?? _originOf(url);
    final HeadlessInAppWebView page = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(host)),
      initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
    );
    await page.run();
    try {
      final InAppWebViewController? controller = page.webViewController;
      if (controller == null) {
        throw const WebViewBridgeException('WebView 承载页未就绪');
      }
      final Object? raw = await controller
          .evaluateJavascript(
            source: _xhrScript(
              url: url,
              method: method,
              headers: headers,
              body: body,
            ),
          )
          .timeout(timeout);
      final Object? decoded = raw is String ? jsonDecode(raw) : null;
      if (decoded is! Map) {
        throw const WebViewBridgeException('页面 XHR 结果解析失败');
      }
      final Map<String, Object?> m = decoded.cast<String, Object?>();
      final Object? rawHeaders = m['headers'];
      final Map<String, String> rh = rawHeaders is Map
          ? <String, String>{
              for (final MapEntry<Object?, Object?> e in rawHeaders.entries)
                e.key.toString(): '${e.value}',
            }
          : const <String, String>{};
      return (
        status: (m['status'] as num?)?.toInt() ?? 0,
        body: '${m['body'] ?? ''}',
        headers: rh,
      );
    } on TimeoutException {
      throw const WebViewBridgeException('页面 XHR 超时');
    } finally {
      await page.dispose();
    }
  }

  @override
  Future<String> currentCookieString({String? domain}) async {
    _ensureAvailable();
    final CookieManager cookieManager = CookieManager.instance();
    final List<Cookie> cs = domain == null || domain.isEmpty
        ? await cookieManager.getAllCookies()
        : await cookieManager.getCookies(
            url: WebUri.https(domain, '/'),
          );
    return cs.map((Cookie c) => '${c.name}=${c.value}').join('; ');
  }

  /// 同源承载页 origin（无法解析时退回 `about:blank`）。
  static String _originOf(String url) {
    final Uri? u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return 'about:blank';
    return '${u.scheme}://${u.host}';
  }

  /// 同步 XHR 脚本（对齐 iOS 桥在页面上下文发请求的语义）。
  static String _xhrScript({
    required String url,
    required String method,
    required Map<String, String> headers,
    String? body,
  }) {
    final String h = jsonEncode(headers);
    final String b = body == null ? 'null' : jsonEncode(body);
    return '''
(function(){
  try {
    var x = new XMLHttpRequest();
    x.open(${jsonEncode(method)}, ${jsonEncode(url)}, false);
    var hs = $h;
    for (var k in hs) { x.setRequestHeader(k, hs[k]); }
    x.send($b);
    var rh = {};
    x.getAllResponseHeaders().trim().split('\\r\\n').forEach(function(line){
      var i = line.indexOf(':');
      if (i > 0) { rh[line.slice(0, i).trim().toLowerCase()] = line.slice(i + 1).trim(); }
    });
    return JSON.stringify({status: x.status, body: x.responseText, headers: rh});
  } catch (e) {
    return JSON.stringify({status: 0, body: '' + e, headers: {}});
  }
})()
''';
  }
}