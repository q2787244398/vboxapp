/// 平台层：DNS 缓存统一层（批次 E · E3-2，零消费键 `dns_cache_clear` 收口）。
///
/// 对齐 iOS `AppSettings.swift` 的「DNS 缓存清理」开关语义：
///  - 启动时 [install] 全局 [HttpOverrides]：所有 `HttpClient` 的连接工厂
///    经 [lookup] 走带 TTL 的进程级 DNS 缓存；
///  - 设置页开关触发 [clear]：清空缓存并 toast（下一次连接重新解析）。
///
/// 落地差异（登记）：iOS 侧清的是 URLCache/DNS 桥接层；Dart 侧无系统 DNS
/// API，以 [InternetAddress.lookup] 结果缓存 + 连接工厂注入实现等价语义。
library;

import 'dart:async';
import 'dart:io';

/// DNS 缓存（进程级单例状态；全部静态成员）。
abstract final class VboxDnsCache {
  static final Map<String, List<InternetAddress>> _cache =
      <String, List<InternetAddress>>{};
  static final Map<String, DateTime> _stamps = <String, DateTime>{};

  /// 缓存 TTL（对齐常见系统 DNS TTL 档位；清理键触发时全量失效）。
  static Duration ttl = const Duration(minutes: 5);

  /// 缓存命中数（调试观察用）。
  static int hits = 0;

  static void clear() {
    _cache.clear();
    _stamps.clear();
    hits = 0;
  }

  /// 带缓存的域名解析（TTL 过期 / 未命中 → 重新 lookup 回填）。
  static Future<List<InternetAddress>> lookup(String host) async {
    final List<InternetAddress>? cached = _cache[host];
    final DateTime? stamp = _stamps[host];
    if (cached != null &&
        stamp != null &&
        DateTime.now().difference(stamp) < ttl) {
      hits++;
      return cached;
    }
    final List<InternetAddress> fresh = await InternetAddress.lookup(host);
    _cache[host] = fresh;
    _stamps[host] = DateTime.now();
    return fresh;
  }

  /// 安装全局 HttpOverrides（main.dart 启动调用一次；幂等）。
  ///
  /// 测试环境（`FLUTTER_TEST`）跳过：FakeAsync 区内真实 IO（DNS lookup）
  /// 永不完成，connectionFactory 会令请求挂起、超时 Timer 泄漏，破坏
  /// flutter_test 的 pending-timer 不变量。
  static void install() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    HttpOverrides.global = _VboxHttpOverrides();
  }
}

/// 全局 HttpOverrides：新建 HttpClient 时注入经缓存的连接工厂。
class _VboxHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final HttpClient client = super.createHttpClient(context);
    // 直连场景走缓存解析（代理场景 host 已是代理地址，同样受益于缓存）。
    client.connectionFactory = (
      Uri uri,
      String? proxyHost,
      int? proxyPort,
    ) {
      final String host = proxyHost ?? uri.host;
      final int port = proxyPort ?? uri.port;
      return _connectViaCache(host, port);
    };
    return client;
  }

  /// 逐地址尝试连接（缓存解析序；TLS 升级由 HttpClient 按 uri.host 完成）。
  Future<ConnectionTask<Socket>> _connectViaCache(String host, int port) async {
    final List<InternetAddress> addrs = await VboxDnsCache.lookup(host);
    if (addrs.isEmpty) {
      throw SocketException('DNS 解析结果为空: $host');
    }
    return Socket.startConnect(addrs.first, port);
  }
}
