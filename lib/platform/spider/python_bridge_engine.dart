/// 平台层：Python 桥接引擎（子进程 stdio ABI）。
///
/// 对齐 iOS `PythonSpiderEngine` 的脚本执行语义，采用**常驻子进程 + JSON over stdio**：
/// `loadScript` 将脚本写入临时 .py 并以 `python3 -u <script>` 启动常驻进程；
/// 脚本输出 `READY` 行后，宿主经 stdin 写 ABI 请求行、stdout 读响应行。
///
/// 测试：使用 `conformance/fixtures/python_echo_spider.py`（真实 python3 子进程），
/// 不可用时（环境无 python3）跳过，不破坏门禁全绿。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../../domain/entities/spider/engine_type.dart';
import '../../domain/entities/spider/spider_engine.dart';
import '../../domain/entities/spider/spider_models.dart';
import 'spider_abi.dart';

/// Python 桥接引擎（实现 [SpiderEngine]）。
class PythonBridgeEngine implements SpiderEngine {
  /// [pythonExecutable] 可注入（测试用 `python3`）。
  PythonBridgeEngine({
    this.pythonExecutable = 'python3',
    SpiderAbiCodec? codec,
    this.timeout = const Duration(seconds: 15),
  }) : _codec = codec ?? const SpiderAbiCodec();

  final String pythonExecutable;
  final Duration timeout;
  final SpiderAbiCodec _codec;

  Process? _process;
  StreamSubscription<String>? _sub;
  final Queue<Completer<String>> _pending = Queue<Completer<String>>();
  bool _ready = false;

  @override
  void Function(String)? onLog;

  /// 平台适配：桥接引擎统一为 python 类型（无 python 枚举以外的细分）。
  @override
  SpiderEngineType get engineType => SpiderEngineType.python;

  // ─────────────── 生命周期 ───────────────

  @override
  Future<void> loadScript(String script) async {
    await dispose();
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
    final String? line;
    try {
      line = await ready.future.timeout(timeout);
    } on TimeoutException {
      await dispose();
      throw const SpiderException(
        SpiderErrorCode.scriptLoad,
        'Python 桥启动超时：进程未输出 READY',
      );
    }
    if (line != 'READY') {
      await dispose();
      throw SpiderException(
        SpiderErrorCode.scriptLoad,
        'Python 桥启动失败：首个输出为「$line」',
      );
    }
    _ready = true;
    onLog?.call('Python 桥：脚本加载完成（子进程 $pythonExecutable）');
  }

  @override
  Future<void> loadLibrary(String script) async {}

  @override
  Future<void> loadScriptFromURL(String urlString) async {
    throw const SpiderException(
      SpiderErrorCode.scriptLoad,
      'Python 桥不支持从 URL 加载脚本（需本地 .py 文件内容）',
    );
  }

  @override
  Future<void> registerSpider() async {
    // Python 桥视脚本 ABI 循环就绪即已注册
    _ready = true;
  }

  @override
  bool get isSpiderReady => _ready;

  // ─────────────── 5 个操作 ───────────────

  @override
  Future<HomeContentResult> callHomeContent() => _roundTrip<HomeContentResult>(
        op: 'homeContent',
        params: const <String, Object?>{},
        parse: HomeContentResult.fromJson,
      );

  @override
  Future<SearchContentResult> callSearchContent(String keyword, int pg) =>
      _roundTrip<SearchContentResult>(
        op: 'searchContent',
        params: <String, Object?>{'keyword': keyword, 'pg': pg},
        parse: SearchContentResult.fromJson,
      );

  @override
  Future<CategoryContentResult> callCategoryContent(
          String tid, int pg, String extend) =>
      _roundTrip<CategoryContentResult>(
        op: 'categoryContent',
        params: <String, Object?>{'tid': tid, 'pg': pg, 'extend': extend},
        parse: CategoryContentResult.fromJson,
      );

  @override
  Future<DetailContentResult> callDetailContent(String ids) =>
      _roundTrip<DetailContentResult>(
        op: 'detailContent',
        params: <String, Object?>{'ids': ids},
        parse: DetailContentResult.fromJson,
      );

  @override
  Future<PlayerContentResult> callPlayerContent(
          String vodId, String flag, String url) =>
      _roundTrip<PlayerContentResult>(
        op: 'playerContent',
        params: <String, Object?>{'vodId': vodId, 'flag': flag, 'url': url},
        parse: PlayerContentResult.fromJson,
      );

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    final Process? p = _process;
    _process = null;
    _ready = false;
    _pending.clear();
    if (p != null) {
      p.kill();
    }
    await p?.exitCode;
  }

  // ─────────────── 内部 ───────────────

  void _onLine(String line) {
    if (_pending.isNotEmpty) {
      _pending.removeFirst().complete(line);
    } else if (line.trim().isNotEmpty) {
      onLog?.call('[py] $line');
    }
  }

  Future<T> _roundTrip<T>({
    required String op,
    required Map<String, Object?> params,
    required T Function(Map<String, Object?>) parse,
  }) async {
    final Process? p = _process;
    if (p == null || !_ready) {
      throw const SpiderException(
        SpiderErrorCode.register,
        'Python 桥未就绪：请先 loadScript + registerSpider',
      );
    }
    final Map<String, Object?> req = _codec.encodeRequest(op, params);
    final Completer<String> c = Completer<String>();
    _pending.add(c);
    p.stdin.writeln(jsonEncode(req));
    final String line;
    try {
      line = await c.future.timeout(timeout);
    } on TimeoutException {
      throw SpiderException(SpiderErrorCode.timeout, '$op 超时（Python 桥）');
    }
    final AbiResponse r = _codec.decodeResponse(line);
    for (final String log in r.logs) {
      onLog?.call(log);
    }
    return parse(r.data ?? const <String, Object?>{});
  }
}
