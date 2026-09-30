/// 平台层单测：Spider 引擎工厂（按引擎类型分派 Node/Python/QuickJS 桥接适配器）。
///
/// 对齐 `contract/docs/abi_v1.md` §1「引擎类型」+ §1.1「引擎选择规则」：
/// - node / nodeLX → [NodeBridgeEngine]（HTTP 桥，58080 / 58083）
/// - python → [PythonBridgeEngine]（子进程 stdio ABI）
/// - quickJS → [QuickJSBridgeEngine]（FFI 原生绑定，G-03-B 已交付）
/// - javaScriptCore → iOS 原生保留，Flutter 以 QuickJS 顶替，抛 [SpiderException]
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/domain/entities/spider/engine_type.dart';
import 'package:vbox/domain/entities/spider/spider_engine.dart';
import 'package:vbox/platform/runtime/quickjs_bridge_engine.dart';
import 'package:vbox/platform/runtime/quickjs_ffi.dart';
import 'package:vbox/platform/spider/node_bridge_engine.dart';
import 'package:vbox/platform/spider/node_http_client.dart';
import 'package:vbox/platform/spider/python_bridge_engine.dart';
import 'package:vbox/platform/spider/spider_engine_factory.dart';

/// FFI mock：可用桥（G-03-B 工厂分派验证用）。
class _FakeQuickJsBridge implements QuickJsNativeBridge {
  @override
  bool get isAvailable => true;

  @override
  int createRuntime() => 0x1000;

  @override
  int createContext(int runtime) => 0x2000;

  @override
  void freeContext(int context) {}

  @override
  void freeRuntime(int runtime) {}

  @override
  String? eval(int context, String script) {
    if (script == 'typeof globalThis.__JS_SPIDER__') return 'object';
    return '';
  }
}

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

    test('quickJS → QuickJSBridgeEngine（FFI 原生绑定，G-03-B）', () async {
      final SpiderEngine engine = factory.create(
        SpiderEngineType.quickJS,
        quickJsBridge: _FakeQuickJsBridge(),
        siteKey: 'js_示例',
        baseUrl: 'https://example.com/js/demo.js',
        requestId: 'req-factory-qjs',
      );
      expect(engine, isA<QuickJSBridgeEngine>());
      expect(engine.engineType, SpiderEngineType.quickJS);
      await engine.loadScript('var spider = {homeContent: function(){return {};}};');
      await engine.registerSpider();
      expect(engine.isSpiderReady, isTrue);
      await engine.dispose();
    });

    test('javaScriptCore → unimplemented（iOS 原生保留，Flutter 以 QuickJS 顶替）', () {
      expect(
        () => factory.create(SpiderEngineType.javaScriptCore),
        throwsA(
          isA<SpiderException>().having(
            (SpiderException e) => e.code,
            'code',
            SpiderErrorCode.unimplemented,
          ),
        ),
      );
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
