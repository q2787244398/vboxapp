/// 平台层：Python 运行时抽象（Wave G · RT-运1）。
///
/// 蜘蛛脚本一律按 `contract/docs/abi_v1.md` §7 的 **stdio ABI** 编写：脚本先
/// `print('READY')`，随后逐行读请求、逐行写响应。运行该脚本的「宿主」有两类：
///
///  - [StdioPythonRuntime]：桌面 / 测试 —— `python3 -u <script>` 常驻**子进程**，
///    宿主经 stdin/stdout 交换行（本仓库原有实现）；
///  - [ChannelPythonRuntime]：Android —— Android 无 `python3` 可执行文件，
///    改由 Chaquopy 把 CPython 解释器随 APK 打包，经平台通道
///    `com.vbox.python/python` 在**进程内**运行同一份脚本（RT-运1）。
///
/// 二者对上层（[PythonBridgeEngine]）暴露完全相同的语义，故引擎对宿主无感知。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/entities/spider/spider_engine.dart';

/// 蜘蛛脚本运行时（常驻 + 逐行 JSON ABI）。
abstract class PythonRuntime {
  /// 按平台选择运行时：Android 走 Chaquopy 进程内（[ChannelPythonRuntime]），
  /// 其余平台走 `python3` 子进程（[StdioPythonRuntime]）。
  factory PythonRuntime.forCurrentPlatform({
    String pythonExecutable = 'python3',
    Duration timeout = const Duration(seconds: 15),
  }) =>
      Platform.isAndroid
          ? ChannelPythonRuntime(timeout: timeout)
          : StdioPythonRuntime(
              pythonExecutable: pythonExecutable,
              timeout: timeout,
            );

  /// 运行时日志（含降级事件）。
  void Function(String)? onLog;

  /// 运行时标签（日志用，如「子进程 python3」/「Android Chaquopy 进程内运行时」）。
  String get runtimeLabel;

  /// 启动并等待脚本输出 `READY`；失败抛 [SpiderException]（`scriptLoad`）。
  Future<void> launch(String script);

  /// 写入一行请求，返回一行响应；超时抛 [SpiderException]（`timeout`）。
  Future<String> roundTrip(String requestLine);

  /// 关闭运行时（幂等）。
  Future<void> shutdown();
}

/// 子进程运行时（`python3 -u <script>` + stdio ABI；桌面 / 测试）。
class StdioPythonRuntime implements PythonRuntime {
  /// [pythonExecutable] 可注入（测试用 `python3`）。
  StdioPythonRuntime({
    this.pythonExecutable = 'python3',
    this.timeout = const Duration(seconds: 15),
  });

  final String pythonExecutable;
  final Duration timeout;

  Process? _process;
  StreamSubscription<String>? _sub;
  final Queue<Completer<String>> _pending = Queue<Completer<String>>();

  @override
  void Function(String)? onLog;

  @override
  String get runtimeLabel => '子进程 $pythonExecutable';

  @override
  Future<void> launch(String script) async {
    await shutdown();
    final File tmp = File(
      '${Directory.systemTemp.path}/vbox_py_spider_'
      '${DateTime.now().microsecondsSinceEpoch}.py',
    );
    await tmp.writeAsString(script);
    final Process p = await Process.start(
      pythonExecutable,
      <String>['-u', tmp.path],
    );
    _process = p;
    _sub = p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);

    // 等待脚本 READY 行
    final Completer<String> ready = Completer<String>();
    _pending.add(ready);
    final String line;
    try {
      line = await ready.future.timeout(timeout);
    } on TimeoutException {
      await shutdown();
      throw const SpiderException(
        SpiderErrorCode.scriptLoad,
        'Python 桥启动超时：进程未输出 READY',
      );
    }
    if (line != 'READY') {
      await shutdown();
      throw SpiderException(
        SpiderErrorCode.scriptLoad,
        'Python 桥启动失败：首个输出为「$line」',
      );
    }
  }

  @override
  Future<String> roundTrip(String requestLine) async {
    final Process? p = _process;
    if (p == null) {
      throw const SpiderException(
        SpiderErrorCode.register,
        'Python 桥未就绪：请先 loadScript + registerSpider',
      );
    }
    final Completer<String> c = Completer<String>();
    _pending.add(c);
    p.stdin.writeln(requestLine);
    try {
      return await c.future.timeout(timeout);
    } on TimeoutException {
      throw const SpiderException(SpiderErrorCode.timeout, 'Python 桥响应超时');
    }
  }

  @override
  Future<void> shutdown() async {
    await _sub?.cancel();
    _sub = null;
    final Process? p = _process;
    _process = null;
    _pending.clear();
    if (p != null) {
      p.kill();
    }
    await p?.exitCode;
  }

  void _onLine(String line) {
    if (_pending.isNotEmpty) {
      _pending.removeFirst().complete(line);
    } else if (line.trim().isNotEmpty) {
      onLog?.call('[py] $line');
    }
  }
}

/// 通道运行时（Android · Chaquopy 进程内解释器；RT-运1）。
///
/// 与原生 `PythonPlugin.kt` 的 `com.vbox.python/python` 通道对齐：
///  - `launch`（`script` / `timeoutMs`）→ `null`（等待脚本 `READY`）
///  - `request`（`line` / `timeoutMs`）→ 一行响应
///  - `shutdown` → `null`
///
/// 通道未注册（未接入 Chaquopy / 非 Android）时抛 `E_UNIMPLEMENTED`，
/// 上层可据此降级提示，不 crash。
class ChannelPythonRuntime implements PythonRuntime {
  ChannelPythonRuntime({
    this.timeout = const Duration(seconds: 15),
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(channelName);

  /// 原生通道名（与 `PythonPlugin.CHANNEL` 一致）。
  static const String channelName = 'com.vbox.python/python';

  /// 通道调用兜底宽限：原生侧已按 [timeout] 先回，此为防原生线程卡死的安全网。
  static const Duration _backstop = Duration(seconds: 5);

  final Duration timeout;
  final MethodChannel _channel;

  @override
  void Function(String)? onLog;

  @override
  String get runtimeLabel => 'Android Chaquopy 进程内运行时';

  Duration get _budget => timeout + _backstop;

  @override
  Future<void> launch(String script) async {
    try {
      await _channel.invokeMethod<void>('launch', <String, Object?>{
        'script': script,
        'timeoutMs': timeout.inMilliseconds,
      }).timeout(_budget);
    } on TimeoutException {
      throw const SpiderException(
        SpiderErrorCode.scriptLoad,
        'Python 桥启动超时：未输出 READY',
      );
    } on MissingPluginException {
      throw const SpiderException(
        SpiderErrorCode.unimplemented,
        'Python 运行时不可用：Android Chaquopy 通道未注册',
      );
    } on PlatformException catch (e) {
      throw SpiderException(
        SpiderErrorCode.scriptLoad,
        e.message ?? 'Python 运行时启动失败',
      );
    }
  }

  @override
  Future<String> roundTrip(String requestLine) async {
    try {
      final String? resp =
          await _channel.invokeMethod<String>('request', <String, Object?>{
        'line': requestLine,
        'timeoutMs': timeout.inMilliseconds,
      }).timeout(_budget);
      return resp ?? '';
    } on TimeoutException {
      throw const SpiderException(SpiderErrorCode.timeout, 'Python 桥响应超时');
    } on MissingPluginException {
      throw const SpiderException(
        SpiderErrorCode.unimplemented,
        'Python 运行时不可用：Android Chaquopy 通道未注册',
      );
    } on PlatformException catch (e) {
      if (e.code == 'E_TIMEOUT') {
        throw SpiderException(
          SpiderErrorCode.timeout,
          e.message ?? 'Python 桥响应超时',
        );
      }
      throw SpiderException(
        SpiderErrorCode.runtime,
        e.message ?? 'Python 运行时调用失败',
      );
    }
  }

  @override
  Future<void> shutdown() async {
    try {
      await _channel.invokeMethod<void>('shutdown');
    } on MissingPluginException {
      // 通道未注册（非 Android / 未接入）→ 无需关闭。
    } on PlatformException {
      // 关闭失败不阻断（幂等语义）。
    }
  }
}
