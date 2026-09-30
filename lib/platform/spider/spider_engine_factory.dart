/// 平台层：Spider 引擎工厂（按引擎类型分派适配器）。
///
/// 对齐契约 §1「引擎类型」+ §1.1「引擎选择规则」：
/// - node / nodeLX → [NodeBridgeEngine]（HTTP 桥，58080 / 58083）
/// - python → [PythonBridgeEngine]（子进程 stdio ABI）
/// - quickJS / javaScriptCore → 需原生绑定（G-03-B 待决策），抛 [SpiderException]
library;

import '../../domain/entities/spider/engine_type.dart';
import '../../domain/entities/spider/spider_engine.dart';
import 'node_bridge_engine.dart';
import 'node_http_client.dart';
import 'python_bridge_engine.dart';

/// Spider 引擎工厂。
class SpiderEngineFactory {
  /// 构造（可注入依赖便于测试）。
  const SpiderEngineFactory();

  /// 按引擎类型创建引擎适配器。
  ///
  /// [nodeClient] 可注入（测试用 fake）；缺省为本机 Node 进程客户端。
  SpiderEngine create(
    SpiderEngineType type, {
    NodeHttpClient? nodeClient,
    String? siteKey,
    String? baseUrl,
    String? requestId,
  }) {
    switch (type) {
      case SpiderEngineType.node:
      case SpiderEngineType.nodeLX:
        return NodeBridgeEngine(
          engineType: type,
          client: nodeClient ??
              LocalNodeHttpClient(
                port: type == SpiderEngineType.nodeLX ? 58083 : 58080,
              ),
          siteKey: siteKey,
          baseUrl: baseUrl,
          requestId: requestId,
        );
      case SpiderEngineType.python:
        return PythonBridgeEngine();
      case SpiderEngineType.quickJS:
      case SpiderEngineType.javaScriptCore:
        throw SpiderException(
          SpiderErrorCode.unimplemented,
          '${type.displayName} 引擎需原生绑定（G-03-B 待决策，见 VBOX_PLAN）',
        );
    }
  }
}
