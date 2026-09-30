/// 平台层单测：Python 桥接引擎（真实 python3 子进程 + stdio ABI）。
///
/// 使用 `conformance/fixtures/python_echo_spider.py` 作为常驻脚本：
/// 脚本输出 `READY` 行后进入 ABI 循环，宿主经 stdin 写请求行、stdout 读响应行
/// （对齐 `contract/docs/abi_v1.md` §7「ABI 消息示例」）。
///
/// 环境无 python3 时整组跳过（`skip`），不破坏门禁全绿。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/domain/entities/spider/engine_type.dart';
import 'package:vbox/domain/entities/spider/spider_engine.dart';
import 'package:vbox/domain/entities/spider/spider_models.dart';
import 'package:vbox/platform/spider/python_bridge_engine.dart';

/// 环境是否可用 python3（同步探测，便于静态 `skip` 判定）。
bool _pythonAvailable() {
  try {
    return Process.runSync('python3', <String>['--version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// 读取回显脚本内容（fixtures 常驻脚本）。
String _echoScript() =>
    File('conformance/fixtures/python_echo_spider.py').readAsStringSync();

void main() {
  final bool hasPython = _pythonAvailable();
  // `skip:` 参数为 Object：false = 不跳过；String = 跳过并显示原因
  final Object skip = hasPython ? false : '环境无 python3，跳过子进程测试';

  group('PythonBridgeEngine（真实 python3 子进程）', () {
    test('loadScript：等待 READY + homeContent 往返', () async {
      final PythonBridgeEngine engine = PythonBridgeEngine();
      try {
        await engine.loadScript(_echoScript());
        await engine.registerSpider();
        expect(engine.isSpiderReady, isTrue);

        final HomeContentResult r = await engine.callHomeContent();
        expect(r.classes, hasLength(3));
        expect(r.classes!.first.typeName, '电影');
        expect(r.list, hasLength(1));
        expect(r.list!.first.vodId, '1001');
        expect(r.list!.first.vodRemarks, '更新至12集');
      } finally {
        await engine.dispose();
      }
    }, skip: skip);

    test('searchContent：keyword 透传脚本（脚本拼「影片」后缀）', () async {
      final PythonBridgeEngine engine = PythonBridgeEngine();
      try {
        await engine.loadScript(_echoScript());
        await engine.registerSpider();

        final SearchContentResult r = await engine.callSearchContent('庆余年', 1);
        expect(r.page, 1);
        expect(r.pagecount, 5);
        expect(r.list, hasLength(1));
        expect(r.list!.first.vodName, '庆余年影片');
      } finally {
        await engine.dispose();
      }
    }, skip: skip);

    test('剩余 3 个操作：category/detail/player 全链路', () async {
      final PythonBridgeEngine engine = PythonBridgeEngine();
      try {
        await engine.loadScript(_echoScript());
        await engine.registerSpider();

        final CategoryContentResult c =
            await engine.callCategoryContent('1', 1, '');
        expect(c.page, 1);
        expect(c.limit, 20);
        expect(c.total, 200);
        expect(c.list, isEmpty);

        final DetailContentResult d = await engine.callDetailContent('1001');
        expect(d.list, hasLength(1));
        expect(d.list!.first.vodName, '示例影片');

        final PlayerContentResult p = await engine.callPlayerContent(
          '1001',
          '线路1',
          'https://cdn.example.com/ep1.m3u8',
        );
        expect(p.parse, 0);
        expect(p.url, 'https://cdn.example.com/ep1.m3u8');
        expect(p.urls, hasLength(1));
        expect(p.urls!.first, 'https://cdn.example.com/ep1.m3u8');
      } finally {
        await engine.dispose();
      }
    }, skip: skip);

    test('未 loadScript 即调用 → register 错误', () async {
      final PythonBridgeEngine engine = PythonBridgeEngine();
      try {
        expect(
          () => engine.callSearchContent('x', 1),
          throwsA(
            isA<SpiderException>().having(
              (SpiderException e) => e.code,
              'code',
              SpiderErrorCode.register,
            ),
          ),
        );
      } finally {
        await engine.dispose();
      }
    }, skip: skip);

    test('首行非 READY → scriptLoad 错误（不等待超时）', () async {
      final PythonBridgeEngine engine = PythonBridgeEngine();
      try {
        await expectLater(
          engine.loadScript("print('hello')\n"),
          throwsA(
            isA<SpiderException>().having(
              (SpiderException e) => e.code,
              'code',
              SpiderErrorCode.scriptLoad,
            ),
          ),
        );
      } finally {
        await engine.dispose();
      }
    }, skip: skip);

    test('脚本语法错误（无 READY 输出）→ scriptLoad 错误（超时分支）', () async {
      final PythonBridgeEngine engine =
          PythonBridgeEngine(timeout: const Duration(seconds: 2));
      try {
        await expectLater(
          engine.loadScript('def broken(\n'),
          throwsA(
            isA<SpiderException>().having(
              (SpiderException e) => e.code,
              'code',
              SpiderErrorCode.scriptLoad,
            ),
          ),
        );
      } finally {
        await engine.dispose();
      }
    }, skip: skip);

    test('loadScriptFromURL → 不支持（scriptLoad）', () async {
      final PythonBridgeEngine engine = PythonBridgeEngine();
      try {
        expect(
          () => engine.loadScriptFromURL('https://x.com/spider.py'),
          throwsA(
            isA<SpiderException>().having(
              (SpiderException e) => e.code,
              'code',
              SpiderErrorCode.scriptLoad,
            ),
          ),
        );
      } finally {
        await engine.dispose();
      }
    }, skip: skip);
  });

  group('PythonBridgeEngine（纯逻辑，无子进程）', () {
    test('engineType 恒为 python', () {
      final PythonBridgeEngine engine = PythonBridgeEngine();
      expect(engine.engineType, SpiderEngineType.python);
      expect(engine.isSpiderReady, isFalse);
    });
  });
}
