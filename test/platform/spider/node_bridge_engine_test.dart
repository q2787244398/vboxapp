/// 平台层单测：Node / NodeLX 桥接引擎（注入 fake HTTP 客户端）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/domain/entities/spider/engine_type.dart';
import 'package:vbox/domain/entities/spider/spider_engine.dart';
import 'package:vbox/domain/entities/spider/spider_models.dart';
import 'package:vbox/platform/spider/node_bridge_engine.dart';
import 'package:vbox/platform/spider/node_http_client.dart';

/// 记录请求并返回预设响应的 fake 客户端。
class _FakeNodeClient implements NodeHttpClient {
  _FakeNodeClient(this._responses);

  final List<Map<String, Object?>> _responses;

  /// 捕获的请求（body JSON）。
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  /// 捕获的请求路径。
  final List<String> paths = <String>[];

  /// 请求次数。
  int callCount = 0;

  /// 强制抛出的异常。
  Object? throwOnPost;

  @override
  Future<String> postJson(String path, String body) async {
    if (throwOnPost != null) throw throwOnPost!;
    callCount++;
    paths.add(path);
    requests.add(jsonDecode(body).cast<String, Object?>());
    final Map<String, Object?> r = _responses[callCount - 1];
    return jsonEncode(r);
  }

  @override
  Future<void> close() async {}
}

Map<String, Object?> _ok(Map<String, Object?> data) => <String, Object?>{
      'ok': true,
      'data': data,
      'logs': <String>['[SPIDER] done'],
      'elapsedMs': 12,
    };

/// 返回非 JSON 文本的客户端（验证协议错误路径）。
class _BadClient implements NodeHttpClient {
  @override
  Future<String> postJson(String path, String body) async => 'oops';

  @override
  Future<void> close() async {}
}

void main() {
  group('NodeBridgeEngine', () {
    test('searchContent：构造 ABI 请求 + 解析响应', () async {
      final _FakeNodeClient client = _FakeNodeClient(<Map<String, Object?>>[
        _ok(<String, Object?>{
          'page': 1,
          'pagecount': 5,
          'list': <Map<String, Object?>>[
            <String, Object?>{
              'vod_id': '2001',
              'vod_name': '测试影片',
              'vod_pic': 'https://cdn.example.com/2001.jpg',
            },
          ],
        }),
      ]);
      final NodeBridgeEngine engine = NodeBridgeEngine(
        engineType: SpiderEngineType.node,
        client: client,
        siteKey: 'js_剧迷',
        baseUrl: 'https://example.com/js/jumi.js',
        requestId: 'req-1',
      );
      await engine.registerSpider();
      expect(engine.isSpiderReady, isTrue);

      final SearchContentResult r = await engine.callSearchContent('测试', 1);

      expect(client.callCount, 1);
      expect(client.requests[0]['op'], 'searchContent');
      final Map<String, Object?> params =
          (client.requests[0]['params'] as Map).cast<String, Object?>();
      expect(params['keyword'], '测试');
      expect(params['pg'], 1);
      final Map<String, Object?> ctx =
          (client.requests[0]['ctx'] as Map).cast<String, Object?>();
      expect(ctx['siteKey'], 'js_剧迷');
      expect(ctx['engineType'], 'Node');
      expect(ctx['timeoutMs'], 15000);

      expect(r.page, 1);
      expect(r.list, hasLength(1));
      expect(r.list!.first.vodName, '测试影片');
      await engine.dispose();
    });

    test('homeContent：请求路径为 /spider/ + 解析 classes', () async {
      final _FakeNodeClient client = _FakeNodeClient(<Map<String, Object?>>[
        _ok(<String, Object?>{
          'class': <Map<String, Object?>>[
            <String, Object?>{'type_id': '1', 'type_name': '电影'},
          ],
          'list': <Map<String, Object?>>[],
        }),
      ]);
      final NodeBridgeEngine engine = NodeBridgeEngine(
        engineType: SpiderEngineType.nodeLX,
        client: client,
      );
      await engine.registerSpider();

      final HomeContentResult r = await engine.callHomeContent();

      expect(client.requests[0]['op'], 'homeContent');
      expect(client.paths.single, '/spider/');
      expect(r.classes, hasLength(1));
      expect(r.classes!.first.typeName, '电影');
      await engine.dispose();
    });

    test('playerContent：urls 回填', () async {
      final _FakeNodeClient client = _FakeNodeClient(<Map<String, Object?>>[
        _ok(<String, Object?>{
          'parse': 0,
          'url': 'https://cdn.example.com/ep1.m3u8',
          'urls': <String>['https://cdn.example.com/ep1.m3u8'],
        }),
      ]);
      final NodeBridgeEngine engine = NodeBridgeEngine(
        engineType: SpiderEngineType.node,
        client: client,
      );
      await engine.registerSpider();

      final PlayerContentResult r = await engine.callPlayerContent(
        '1001',
        '线路1',
        'https://cdn.example.com/ep1.m3u8',
      );

      expect(r.urls, hasLength(1));
      expect(r.urls!.first, 'https://cdn.example.com/ep1.m3u8');
      await engine.dispose();
    });

    test('错误响应：E_RUNTIME → SpiderException(runtime)', () async {
      final _FakeNodeClient client = _FakeNodeClient(<Map<String, Object?>>[
        <String, Object?>{
          'ok': false,
          'error': <String, Object?>{
            'code': 'E_RUNTIME',
            'message': '进程崩溃',
          },
          'logs': <String>[],
          'elapsedMs': 3,
        },
      ]);
      final NodeBridgeEngine engine = NodeBridgeEngine(
        engineType: SpiderEngineType.node,
        client: client,
      );
      await engine.registerSpider();

      expect(
        () => engine.callSearchContent('x', 1),
        throwsA(
          isA<SpiderException>().having(
            (SpiderException e) => e.code,
            'code',
            SpiderErrorCode.runtime,
          ),
        ),
      );
      await engine.dispose();
    });

    test('非 JSON 响应 → protocol', () async {
      final NodeBridgeEngine engine = NodeBridgeEngine(
        engineType: SpiderEngineType.node,
        client: _BadClient(),
      );
      await engine.registerSpider();

      expect(
        () => engine.callHomeContent(),
        throwsA(
          isA<SpiderException>().having(
            (SpiderException e) => e.code,
            'code',
            SpiderErrorCode.protocol,
          ),
        ),
      );
      await engine.dispose();
    });

    test('传输超时 → timeout', () async {
      final _FakeNodeClient client = _FakeNodeClient(<Map<String, Object?>>[])
        ..throwOnPost = TimeoutException('slow');
      final NodeBridgeEngine engine = NodeBridgeEngine(
        engineType: SpiderEngineType.node,
        client: client,
      );
      await engine.registerSpider();

      expect(
        () => engine.callHomeContent(),
        throwsA(
          isA<SpiderException>().having(
            (SpiderException e) => e.code,
            'code',
            SpiderErrorCode.timeout,
          ),
        ),
      );
      await engine.dispose();
    });

    test('引擎类型断言：仅支持 node / nodeLX', () {
      expect(
        () => NodeBridgeEngine(
          engineType: SpiderEngineType.quickJS,
          client: _FakeNodeClient(const <Map<String, Object?>>[]),
        ),
        throwsAssertionError,
      );
    });
  });
}
