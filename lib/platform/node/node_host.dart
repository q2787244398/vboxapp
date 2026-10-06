/// 平台层：Node 宿主接缝（批次 I · ND-01）。
///
/// iOS 用 **nodejs-mobile 进程内引擎**（`NodeRunner.startEngine` 跑在独立 2MB 栈线程，
/// 见 `vbox/Services/NodeRuntimeManager.swift` L457-L468）。Flutter 无 `ios/` 目标，
/// 故按平台给出两类等价宿主（与 [PythonRuntime] 的「桌面子进程 / Android 通道」同构）：
///
///  - [ProcessNodeHost]：macOS / Windows / 测试 —— `node <runtimeDir>/main.js`
///    常驻**子进程**，端口矩阵经环境变量注入（与 iOS `setenv` 逐项对齐）；
///  - [ChannelNodeHost]：Android —— Android 无 `node` 可执行文件，改由 nodejs-mobile
///    把 Node 引擎随 APK 打包，经平台通道 `com.vbox.node/host` 在**进程内**启动。
///
/// 二者对上层（[NodeRuntimeManager]）语义相同：只管「拉起 / 停止」，
/// **就绪判定与心跳一律走 HTTP 探活**（对齐 iOS，见 ND-01 说明）；故宿主无感知。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Node 宿主异常。
class NodeHostException implements Exception {
  /// 构造。
  const NodeHostException(this.message);

  /// 文案。
  final String message;

  @override
  String toString() => 'NodeHostException($message)';
}

/// 宿主启动参数（对齐 iOS `launchNodeEngine` 的环境变量注入）。
class NodeHostConfig {
  /// 构造。
  const NodeHostConfig({
    required this.runtimeDir,
    required this.mainScript,
    required this.bundlePath,
    required this.lxPluginsDir,
    required this.lxAckPath,
    required this.environment,
  });

  /// Node 运行时根目录（可写，`<appData>/noderuntime`）。
  final String runtimeDir;

  /// 入口脚本绝对路径（`<runtimeDir>/main.js`）。
  final String mainScript;

  /// bundle 绝对路径（`<runtimeDir>/bundles/kstore_index.js`）。
  final String bundlePath;

  /// lx 插件目录（远程源经 ND-03 下发）。
  final String lxPluginsDir;

  /// lx 桥接握手文件路径（对齐 iOS `LX_ACK_PATH`）。
  final String lxAckPath;

  /// 注入的环境变量（`PORT` / `HEALTH_PORT` / `BUNDLE_PATH` / `LX_*` …）。
  final Map<String, String> environment;
}

/// Node 宿主（拉起 / 停止）。
abstract class NodeHost {
  /// 按平台选择宿主：Android 走 [ChannelNodeHost]，其余走 [ProcessNodeHost]。
  factory NodeHost.forCurrentPlatform({
    String nodeExecutable = 'node',
    MethodChannel? channel,
  }) =>
      Platform.isAndroid
          ? ChannelNodeHost(channel: channel)
          : ProcessNodeHost(nodeExecutable: nodeExecutable);

  /// 宿主日志（含降级事件）。
  void Function(String)? onLog;

  /// 宿主标签（日志用）。
  String get hostLabel;

  /// 启动宿主（幂等：先停再起）。
  ///
  /// 失败抛 [NodeHostException]；**不等待就绪**（就绪由上层 HTTP 探活判定）。
  Future<void> start(NodeHostConfig config);

  /// 停止宿主（幂等）。
  Future<void> stop();

  /// 宿主进程 / 引擎是否在运行（不探活）。
  Future<bool> isRunning();
}

/// 子进程宿主（`node <main.js>`；macOS / Windows / 测试）。
class ProcessNodeHost implements NodeHost {
  /// [nodeExecutable] 可注入（测试用；缺省走 PATH 上的 `node`）。
  ProcessNodeHost({this.nodeExecutable = 'node'});

  /// Node 可执行文件（PATH 名或绝对路径）。
  final String nodeExecutable;

  Process? _process;
  StreamSubscription<String>? _outSub;
  StreamSubscription<String>? _errSub;

  @override
  void Function(String)? onLog;

  @override
  String get hostLabel => '子进程 $nodeExecutable';

  @override
  Future<void> start(NodeHostConfig config) async {
    await stop();
    try {
      _process = await Process.start(
        nodeExecutable,
        <String>[config.mainScript],
        workingDirectory: config.runtimeDir,
        environment: config.environment,
        includeParentEnvironment: true,
      );
    } on ProcessException catch (e) {
      throw NodeHostException('Node 宿主启动失败：未找到可执行文件「$nodeExecutable」（${e.message}）');
    }
    _outSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      if (line.trim().isNotEmpty) onLog?.call('[node] $line');
    });
    _errSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      if (line.trim().isNotEmpty) onLog?.call('[node:err] $line');
    });
    onLog?.call('🚀 已拉起 Node 子进程（$nodeExecutable ${config.mainScript}）');
  }

  @override
  Future<void> stop() async {
    await _outSub?.cancel();
    await _errSub?.cancel();
    _outSub = null;
    _errSub = null;
    final Process? p = _process;
    _process = null;
    if (p != null) {
      p.kill();
      await p.exitCode;
    }
  }

  @override
  Future<bool> isRunning() async {
    final Process? p = _process;
    return p != null;
  }
}

/// 通道宿主（Android · nodejs-mobile 进程内引擎）。
///
/// 与原生 `NodePlugin.kt` 的 `com.vbox.node/host` 通道对齐：
///  - `start`（`runtimeDir` / `mainScript` / `bundlePath` / `lxPluginsDir` /
///    `lxAckPath` / `environment`）→ `null`
///  - `stop` → `null`
///  - `isRunning` → `bool`
///
/// 通道未注册（未接入 nodejs-mobile / 非 Android）时抛 `E_NODE_UNAVAILABLE`，
/// 上层据此标记 `node-failed` 并降级提示，**不 crash**。
class ChannelNodeHost implements NodeHost {
  /// 构造。
  ChannelNodeHost({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// 原生通道名（与 `NodePlugin.CHANNEL` 一致）。
  static const String channelName = 'com.vbox.node/host';

  /// 通道调用兜底宽限（防原生线程卡死的安全网）。
  static const Duration _backstop = Duration(seconds: 10);

  final MethodChannel _channel;

  @override
  void Function(String)? onLog;

  @override
  String get hostLabel => 'Android nodejs-mobile 进程内引擎';

  @override
  Future<void> start(NodeHostConfig config) async {
    try {
      await _channel.invokeMethod<void>('start', <String, Object?>{
        'runtimeDir': config.runtimeDir,
        'mainScript': config.mainScript,
        'bundlePath': config.bundlePath,
        'lxPluginsDir': config.lxPluginsDir,
        'lxAckPath': config.lxAckPath,
        'environment': config.environment,
      }).timeout(_backstop);
      onLog?.call('🚀 已拉起 Node 进程内引擎（nodejs-mobile）');
    } on TimeoutException {
      throw const NodeHostException('Node 宿主启动超时：原生引擎未在 10s 内返回');
    } on MissingPluginException {
      throw const NodeHostException('Node 宿主不可用：Android nodejs-mobile 通道未注册');
    } on PlatformException catch (e) {
      throw NodeHostException(e.message ?? 'Node 宿主启动失败（${e.code}）');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop').timeout(_backstop);
    } on TimeoutException {
      // 停止超时不阻断（幂等语义）。
    } on MissingPluginException {
      // 通道未注册 → 无需停止。
    } on PlatformException {
      // 停止失败不阻断。
    }
  }

  @override
  Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isRunning').timeout(_backstop) ??
          false;
    } on TimeoutException {
      return false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// 不可用宿主（未接入平台 / 单测缺省；启动即报错，不 crash）。
class UnavailableNodeHost implements NodeHost {
  /// 构造。
  ///
  /// 非 `const`：[NodeHost.onLog] 为可变字段（宿主日志回调），无法声明常量构造。
  UnavailableNodeHost();

  @override
  void Function(String)? onLog;

  @override
  String get hostLabel => '未接入';

  @override
  Future<void> start(NodeHostConfig config) async =>
      throw const NodeHostException('Node 宿主尚未接入（等待 ND-01-native 运行时二进制）');

  @override
  Future<void> stop() async {}

  @override
  Future<bool> isRunning() async => false;
}