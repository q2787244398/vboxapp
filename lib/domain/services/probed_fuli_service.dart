/// 领域层：带域名探测的原生福利平台服务基类（批次 H · Fuli-S1 / UI-C1b 拆分）。
///
/// 唯一真相源：iOS `vbox/Services/FuliPlatformService.swift`
///   · `probeHost()`（L119-L154）：逐个探测 `allHosts`（自定义域名在前 +
///     默认域名），首个 HTTP 2xx 即就绪；全部失败保持未就绪（**不回退到
///     不可达域名**，便于下次重新探测）。
///
/// 说明：本类原与各平台服务同处 `native_fuli_services.dart`；UI-C1b 批次把
/// 各平台服务拆为一服务一文件（对齐 iOS 的组织方式），基类独立成文件避免
/// 循环 import。
library;

import 'dart:async';

import '../../data/datasources/local/welfare_domain_store.dart';
import '../../platform/spider/spider_http_bridge.dart';
import 'fuli_base_service.dart';

/// 带域名探测的原生福利平台服务基类。
abstract class ProbedFuliService extends FuliBaseService {
  /// 构造（[bridge] 供测试注入假传输）。
  ProbedFuliService({
    required super.platformKey,
    required super.platformName,
    required super.defaultHosts,
    SpiderHttpBridge? bridge,
  }) : _bridge = bridge ?? SpiderHttpBridge();

  final SpiderHttpBridge _bridge;

  /// 底层 HTTP 桥（供子类复用，避免二次自建传输 / 丢失代理与 SSL 配置）。
  SpiderHttpBridge get bridge => _bridge;

  String _probedHost = '';
  bool _ready = false;

  @override
  String get currentHost => _probedHost.isEmpty ? primaryHost : _probedHost;

  @override
  bool get isHostReady => _ready;

  /// 逐个探测可用域名（自定义 → 默认），首个可达即就绪；全部失败保持未就绪。
  Future<void> probeHosts() async {
    for (final String host in allHosts) {
      if (host.trim().isEmpty) continue;
      if (await _reachable(host)) {
        _probedHost = host;
        _ready = true;
        return;
      }
    }
    _probedHost = '';
    _ready = false;
  }

  /// 探测单个域名可达性（HTTP 2xx/3xx；超时 5s，对齐 iOS `reprobe` 口径）。
  Future<bool> _reachable(String host) async {
    final String url = applyProxyIfNeeded(host);
    try {
      final SpiderHttpResult res = await _bridge.request(
        url,
        options: const SpiderHttpOptions(timeout: Duration(seconds: 5)),
      );
      return res.ok;
    } catch (_) {
      return false;
    }
  }

  @override
  void reprobe() {
    unawaited(probeHosts());
  }

  @override
  void resetDomain() {
    WelfareDomainStore.shared.clearDomains(platformName);
    unawaited(probeHosts());
  }
}
