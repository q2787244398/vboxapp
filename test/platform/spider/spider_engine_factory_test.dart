/// 平台层单测：Spider 引擎工厂（按引擎类型分派 Node/Python 桥接适配器）。
///
/// 对齐 `contract/docs/abi_v1.md` §1「引擎类型」+ §1.1「引擎选择规则」：
/// - node / nodeLX → [NodeBridgeEngine]（HTTP 桥，58080 / 58083）
/// - python → [PythonBridgeEngine]（子进程 stdio ABI）
/// - quickJS / javaScriptCore → 需原生绑定（G-03-B 待决策），抛 [SpiderException]
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/domain/entities/spider/engine_type.dart';
import 'package:vbox/domain/entities/spider/spider_engine.dart';
import 'package:vbox/platform/spider/node_bridge_engine.dart';
import 'package:vbox/platform/spider/node_http_client.dart';
import 'package:vbox/platform/spider/python_bridge_engine.dart';
import 'package:vbox/platform/spider/spider_engine_factory.dart';

/// 记录请求并返回预设响应的 fake 客户端（复用 Node 桥测试的响应结构）。
class _FakeNodeClient implements NodeHttpClient {
  final List<Map<String, Object?>> _responses;
  int _index = 0;

  _FakeNodeClient(this._responses);

  @override
  Future<String> postJson(String path, String body) async {
    final Map<String, Object?> r = _responses[_index++];
    return jsonEncode(r);
  }

  @override
  Future<void> close() async {}
}

void main() {
  const SpiderEngineFactory factory = SpiderEngineFactory();

  group('SpiderEngineFactory', () {
    test('node → NodeBridgeEngine（engineType 对齐）', () {
      final SpiderEngine engine = factory.create(SpiderEngineType.node);
      expect(engine, isA<NodeBridgeEngine>());
      expect(engine.engineType, SpiderEngineType.node);
    });

    test('nodeLX → NodeBridgeEngine（engineType 对齐）', () {
      final SpiderEngine engine = factory.create(SpiderEngineType.nodeLX);
      expect(engine, isA<NodeBridgeEngine>());
      expect(engine.engineType, SpiderEngineType.nodeLX);
    });

    test('python → PythonBridgeEngine', () {
      final SpiderEngine engine = factory.create(SpiderEngineType.python);
      expect(engine, isA<PythonBridgeEngine>());
      expect(engine.engineType, SpiderEngineType.python);
    });

    test('quickJS / javaScriptCore → unimplemented（G-03-B 待决策）', () {
      for (final SpiderEngineType t in <SpiderEngineType>[
        SpiderEngineType.quickJS,
        SpiderEngineType.javaScriptCore,
      ]) {
        expect(
          () => factory.create(t),
          throwsA(
            isA<SpiderException>().having(
              (SpiderException e) => e.code,
              'code',
              SpiderErrorCode.unimplemented,
            ),
          ),
        );
      }
    });

    test('注入 fake 客户端：node 引擎 register + homeContent 走 ABI', () async {
      final _FakeNodeClient client = _FakeNodeClient(<Map<String, Object?>>[
        <String, Object?>{
          'ok': true,
          'data': <String, Object?>{
            'class': <Map<String, Object?>>[
              <String, Object?>{'type_id': '1', 'type_name': '电影'},
            ],
            'list': <Map<String, Object?>>[],
          },
        },
      ]);
      final SpiderEngine engine = factory.create(
        SpiderEngineType.node,
        nodeClient: client,
        siteKey: 'js_剧迷',
        baseUrl: 'https://example.com/js/jumi.js',
        requestId: 'req-factory-1',
      );
      expect(engine, isA<NodeBridgeEngine>());
      await engine.registerSpider();
      expect(engine.isSpiderReady, isTrue);

      final dynamic home = await engine.callHomeContent();
      expect(home.classes, hasLength(1));
      expect(home.classes!.first.typeName, '电影');
      await engine.dispose();
    });
  });
}
