/// 平台层：Node 常驻系统运行时管理器测试（批次 I · ND-01）。
///
/// 覆盖对齐 iOS `NodeRuntimeManager` 的 8 类语义：
///   1. 启动全链路（部署 → 完整性 → 拉起 → 探活 → ready）
///   2. 代码文件覆盖 / 数据文件仅首次（保护网盘凭据）
///   3. 启动探活失败 → `node-failed`
///   4. 心跳连续失败判崩溃 → **自动重启**（Flutter 独立宿主能力）
///   5. 崩溃后心跳恢复自愈
///   6. 内存告警降级与恢复
///   7. bundle 内置交付（随包，对齐 iOS folder reference）+ MD5 完整性 + 远端版本探针刷新
///   8. lx-mobile 桥接独立探活
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbox/platform/node/node_host.dart';
import 'package:vbox/platform/node/node_ports.dart';
import 'package:vbox/platform/node/node_runtime_manager.dart';

/// 假宿主：记录调用次数与启动参数，可注水失败。
class _FakeNodeHost implements NodeHost {
  int startCalls = 0;
  int stopCalls = 0;
  NodeHostConfig? lastConfig;
  bool failNextStart = false;

  @override
  void Function(String)? onLog;

  @override
  String get hostLabel => 'fake';

  @override
  Future<void> start(NodeHostConfig config) async {
    startCalls += 1;
    if (failNextStart) {
      failNextStart = false;
      throw const NodeHostException('mock 启动失败');
    }
    lastConfig = config;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<bool> isRunning() async => startCalls > stopCalls;
}

/// 假 HTTP：按端口区分主链路与 lx 链路健康，可注入文本 / 字节体。
class _FakeHttp implements NodeHttpTransport {
  bool healthy = true;
  bool lxHealthy = true;
  final Map<String, String> texts = <String, String>{};
  final Map<String, List<int>> blobs = <String, List<int>>{};

  @override
  Future<int?> statusCode(String url, {Duration? timeout}) async {
    if (url.contains('${NodePorts.lxHealth}')) return lxHealthy ? 200 : null;
    return healthy ? 200 : null;
  }

  @override
  Future<List<int>?> getBytes(String url, {Duration? timeout}) async => blobs[url];

  @override
  Future<String?> getText(String url, {Duration? timeout}) async => texts[url];
}

/// 假资源：内存 map。
class _FakeAssets implements NodeAssetSource {
  _FakeAssets(this._files);

  final Map<String, List<int>> _files;

  @override
  Future<List<int>?> load(String key) async => _files[key];
}

void main() {
  late Directory dir;
  late _FakeNodeHost host;
  late _FakeHttp http;

  /// 内置资源（对齐 iOS `Resources/noderuntime` folder reference：含 6.4MB bundle）。
  ///
  /// [bundle] 传 null 可模拟「资源未随包」（对齐 iOS `bundleResourceMissing`）。
  Map<String, List<int>> assets({String? bundle = 'builtin-bundle'}) => <String, List<int>>{
        'assets/noderuntime/main.js': utf8.encode('// main v2'),
        'assets/noderuntime/node-intl-polyfill.js': utf8.encode('// polyfill'),
        'assets/noderuntime/db.json': utf8.encode('{"k":1}'),
        'assets/noderuntime/default.db.json': utf8.encode('{}'),
        'assets/noderuntime/wexfnwconfig.json': utf8.encode('{"a":1}'),
        'assets/noderuntime/lx/lx-bridge.js': utf8.encode('// lx'),
        if (bundle != null) 'assets/noderuntime/bundles/kstore_index.js': utf8.encode(bundle),
      };

  NodeRuntimeManager build({
    Map<String, List<int>>? files,
    bool ready = true,
  }) {
    host = _FakeNodeHost();
    http = _FakeHttp()..healthy = ready;
    return NodeRuntimeManager(
      host: host,
      http: http,
      assets: _FakeAssets(files ?? assets()),
      runtimeDirPath: dir.path,
      healthInterval: const Duration(hours: 1),
      // 单测注入 1 次探活 + 零间隔，保持用例快速；生产缺省对齐 iOS（12 次 × 500ms）。
      healthProbeRetries: 1,
      healthProbeRetryDelay: Duration.zero,
      lxHealthInterval: const Duration(hours: 1),
      readyProbeRetries: 2,
      readyProbeDelay: Duration.zero,
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vbox_node_rt_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('启动全链路：部署 → 拉起 → 探活 → ready（状态流 starting→ready）', () async {
    final NodeRuntimeManager m = build();
    addTearDown(m.stop);
    final List<NodeRuntimeStatus> seen = <NodeRuntimeStatus>[];
    m.statusStream.listen(seen.add);

    await m.start();

    expect(m.isSystemReady, isTrue);
    expect(m.isCrashed, isFalse);
    expect(m.statusInfo, 'node-ready(58080)');
    expect(host.startCalls, 1);
    // 运行时文件已落盘
    expect(File(m.mainScriptPath).existsSync(), isTrue);
    expect(File('${dir.path}/lx/lx-bridge.js').existsSync(), isTrue);
    expect(Directory(m.lxPluginsDirPath).existsSync(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(seen.first, NodeRuntimeStatus.starting);
    expect(seen.last, NodeRuntimeStatus.ready);
  });

  test('环境变量矩阵与 iOS setenv 1:1', () async {
    final NodeRuntimeManager m = build();
    addTearDown(m.stop);
    await m.start();

    final Map<String, String> env = host.lastConfig!.environment;
    expect(env['PORT'], '58080');
    expect(env['DEV_HTTP_PORT'], '58080');
    expect(env['DART_PORT'], '58081');
    expect(env['HEALTH_PORT'], '58082');
    expect(env['NODE_PATH'], dir.path);
    expect(env['BUNDLE_PATH'], m.activeBundlePath);
    expect(env['LX_PORT'], '58083');
    expect(env['LX_HEALTH_PORT'], '58084');
    expect(host.lastConfig!.mainScript, m.mainScriptPath);
  });

  test('生产缺省对齐 iOS：心跳 12 次 × 500ms / 就绪预算 45s / 阈值与周期一致', () {
    final NodeRuntimeManager m = NodeRuntimeManager(
      host: _FakeNodeHost(),
      http: _FakeHttp(),
      assets: _FakeAssets(assets()),
      runtimeDirPath: dir.path,
    );

    expect(m.healthProbeRetries, 12, reason: '对齐 iOS runHealthCheck → probeHealth(retries: 12)');
    expect(m.healthProbeRetryDelay, const Duration(milliseconds: 500));
    expect(m.readyProbeRetries, 90, reason: '45s 就绪预算（对齐 iOS ack 45s）');
    expect(m.readyProbeDelay, const Duration(milliseconds: 500));
    expect(m.maxHealthFailures, 3);
    expect(m.healthInterval, const Duration(seconds: 30));
    expect(m.lxHealthInterval, const Duration(seconds: 15));
  });

  test('代码文件覆盖 / 数据文件仅首次（保护网盘凭据）', () async {
    await File('${dir.path}/main.js').writeAsString('// OLD');
    await File('${dir.path}/db.json').writeAsString('{"cred":"keep"}');
    final NodeRuntimeManager m = build();
    addTearDown(m.stop);

    await m.start();

    expect(await File(m.mainScriptPath).readAsString(), '// main v2');
    expect(await File('${dir.path}/db.json').readAsString(), '{"cred":"keep"}');
  });

  test('内置资源缺失（main.js）→ 启动失败降级为 node-failed', () async {
    final NodeRuntimeManager m = build(files: <String, List<int>>{});
    addTearDown(m.stop);
    final List<String> crashes = <String>[];
    m.crashStream.listen(crashes.add);

    await m.start();

    expect(m.isSystemReady, isFalse);
    expect(m.status, NodeRuntimeStatus.failed);
    expect(host.startCalls, 0);
    expect(crashes, isNotEmpty);
  });

  test('拉起失败（宿主抛错）→ node-failed', () async {
    final NodeRuntimeManager m = build();
    addTearDown(m.stop);
    host.failNextStart = true;

    await m.start();

    expect(m.status, NodeRuntimeStatus.failed);
    expect(m.lastError, contains('mock 启动失败'));
  });

  test('启动探活失败 → node-failed（就绪以 HTTP 探活为准）', () async {
    final NodeRuntimeManager m = build(ready: false);
    addTearDown(m.stop);

    await m.start();

    expect(m.isSystemReady, isFalse);
    expect(m.status, NodeRuntimeStatus.failed);
    expect(m.lastError, contains('HTTP 探活失败'));
  });

  test('心跳连续 3 次失败 → 判崩溃并自动重启成功', () async {
    final NodeRuntimeManager m = build();
    addTearDown(m.stop);
    await m.start();
    expect(host.startCalls, 1);

    http.healthy = false;
    await m.runHealthCheck();
    await m.runHealthCheck();
    expect(m.isCrashed, isFalse, reason: '未达阈值不判崩溃');
    await m.runHealthCheck(); // 第 3 次 → 崩溃 + 触发重启
    await Future<void>.delayed(Duration.zero);

    expect(host.startCalls, 2, reason: '崩溃后自动重启（Flutter 独立宿主能力）');
  });

  test('崩溃后心跳恢复 → 自愈回 ready', () async {
    final NodeRuntimeManager m = build();
    addTearDown(m.stop);
    await m.start();

    http.healthy = false;
    await m.runHealthCheck();
    await m.runHealthCheck();
    await m.runHealthCheck();
    expect(m.isCrashed, isTrue);

    http.healthy = true;
    await m.runHealthCheck();
    expect(m.isCrashed, isFalse);
    expect(m.isSystemReady, isTrue);
    expect(m.statusInfo, 'node-ready(58080)');
    expect(m.lastError, isNull);
  });

  test('内存告警：仅标记降级，探活恢复后还原 ready', () async {
    final NodeRuntimeManager m = build();
    addTearDown(m.stop);
    await m.start();

    m.handleMemoryWarning();
    expect(m.status, NodeRuntimeStatus.memoryWarning);
    expect(m.isSystemReady, isTrue, reason: '降级不杀 Node（保网盘会话）');

    await m.runHealthCheck();
    expect(m.status, NodeRuntimeStatus.ready);
  });

  test('未就绪时内存告警不覆盖启动态', () async {
    final NodeRuntimeManager m = build();
    addTearDown(m.stop);
    m.handleMemoryWarning();
    expect(m.status, NodeRuntimeStatus.stopped);
  });

  test('bundle 完整性：manifest MD5 一致则放行', () async {
    final NodeRuntimeManager m = build();
    addTearDown(m.stop);
    await Directory(m.bundleDirPath).create(recursive: true);
    final List<int> bytes = utf8.encode('kstore-bundle');
    await File(m.activeBundlePath).writeAsBytes(bytes);
    await m.writeBundleManifest(
      md5Hex: md5.convert(bytes).toString(),
      source: 'remote',
      version: '1.2.3',
    );

    await m.verifyBundleIntegrity();

    expect(await m.readLocalBundleVersion(), '1.2.3');
  });

  test('bundle 完整性：不一致且内置可用 → 回退资源并重建 manifest', () async {
    final NodeRuntimeManager m = build(files: assets(bundle: 'builtin-bundle'));
    addTearDown(m.stop);
    await Directory(m.bundleDirPath).create(recursive: true);
    await File(m.activeBundlePath).writeAsBytes(utf8.encode('corrupted'));

    await m.verifyBundleIntegrity();

    expect(await File(m.activeBundlePath).readAsString(), 'builtin-bundle');
    expect((await m.readBundleManifest())!['source'], 'bundled');
  });

  test('bundle 完整性：内置资源未随包 → 抛错（对齐 iOS bundleResourceMissing）', () async {
    final NodeRuntimeManager m = build(files: assets(bundle: null));
    addTearDown(m.stop);
    await Directory(m.bundleDirPath).create(recursive: true);
    await File(m.activeBundlePath).writeAsBytes(utf8.encode('corrupted'));

    expect(
      () => m.verifyBundleIntegrity(),
      throwsA(isA<NodeHostException>()),
    );
    expect(await m.readBundleManifest(), isNull);
  });

  test('启动即用内置 bundle：落盘 + manifest(source=bundled) + BUNDLE_PATH 指向', () async {
    final NodeRuntimeManager m = build(); // 缺省内置 bundle
    addTearDown(m.stop);
    await m.start();

    expect(await File(m.activeBundlePath).readAsString(), 'builtin-bundle');
    expect((await m.readBundleManifest())!['source'], 'bundled');
    expect(host.lastConfig!.environment['BUNDLE_PATH'], m.activeBundlePath);
  });

  test('远端 bundle 刷新：版本一致 → 跳过下载', () async {
    final NodeRuntimeManager m = build();
    addTearDown(m.stop);
    await m.writeBundleManifest(md5Hex: 'x', source: 'remote', version: '9.9.9');
    http.texts['https://cdn/bundle.ver'] = '9.9.9';
    http.blobs['https://cdn/bundle.js'] = utf8.encode('should-not-be-used');

    await m.refreshBundleIfNeeded('https://cdn/bundle.js', 'https://cdn/bundle.ver');

    expect(File(m.activeBundlePath).existsSync(), isFalse);
  });

  test('远端 bundle 刷新：下载 → ≥1MB 合理性 → 原子写 → manifest(remote)', () async {
    final NodeRuntimeManager m = build();
    addTearDown(m.stop);
    final List<int> big = List<int>.filled(1000001, 7);
    http.blobs['https://cdn/bundle.js'] = big;

    await m.refreshBundleIfNeeded('https://cdn/bundle.js');

    expect(File(m.activeBundlePath).lengthSync(), 1000001);
    final Map<String, Object?> manifest = (await m.readBundleManifest())!;
    expect(manifest['source'], 'remote');
    expect(manifest['md5'], md5.convert(big).toString());
  });

  test('远端 bundle 刷新：体积 < 1MB 视为异常丢弃', () async {
    final NodeRuntimeManager m = build();
    addTearDown(m.stop);
    http.blobs['https://cdn/bundle.js'] = List<int>.filled(999, 1);

    await m.refreshBundleIfNeeded('https://cdn/bundle.js');

    expect(File(m.activeBundlePath).existsSync(), isFalse);
  });

  test('lx 桥接独立探活：成功 → isLXReady；失败不影响主链路', () async {
    final NodeRuntimeManager m = build();
    addTearDown(m.stop);
    await m.start();
    await m.runLXHealthCheck();
    expect(m.isLXReady, isTrue);

    http.lxHealthy = false;
    await m.runLXHealthCheck();
    expect(m.isLXReady, isFalse);
    expect(m.isSystemReady, isTrue, reason: 'kstore 主链路不受 lx 影响');
  });
}