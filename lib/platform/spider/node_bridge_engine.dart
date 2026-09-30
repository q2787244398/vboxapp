/// 平台层：Node / NodeLX 桥接引擎（HTTP ABI）。
///
/// 对齐 iOS 常驻 Node 进程（`127.0.0.1:58080`）+ lx-music 桥接（`127.0.0.1:58083`）。
/// 桥接模型：蜘蛛脚本**常驻远端进程**，宿主经 ABI op（homeContent / searchContent /
/// categoryContent / detailContent / playerContent）经 HTTP 调用；
/// 故 loadScript / loadLibrary / loadScriptFromURL 为 no-op（脚本驻留远端），
/// registerSpider 直接标记 ready。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/entities/spider/engine_type.dart';
import '../../domain/entities/spider/spider_engine.dart';
import '../../domain/entities/spider/spider_models.dart';
import 'node_http_client.dart';
import 'spider_abi.dart';

/// Node / NodeLX 桥接引擎（实现 [SpiderEngine]）。
class NodeBridgeEngine implements SpiderEngine {
  /// [engineType] 须为 node / nodeLX；[client] 可注入（测试用 fake）。
  NodeBridgeEngine({
    required this.engineType,
    required NodeHttpClient client,
    SpiderAbiCodec? codec,
    this.siteKey,
    this.baseUrl,
    this.requestId,
  })  : assert(
          engineType == SpiderEngineType.node ||
              engineType == SpiderEngineType.nodeLX,
          'NodeBridgeEngine 仅支持 node / nodeLX',
        ),
        _client = client,
        _codec = codec ?? const SpiderAbiCodec();

  @override
  final SpiderEngineType engineType;

  /// 站点键（ctx.siteKey）。
  final String? siteKey;

  /// 站点脚本地址（ctx.baseUrl）。
  final String? baseUrl;

  /// 请求追踪号（ctx.requestId）。
  final String? requestId;

  final NodeHttpClient _client;
  final SpiderAbiCodec _codec;
  bool _ready = false;

  @override
  void Function(String)? onLog;

  // ─────────────── 生命周期（桥接 no-op / 立即就绪） ───────────────

  @override
  Future<void> loadScript(String script) async {
    // 桥接模型：脚本驻留远端进程
    onLog?.call('Node 桥：脚本已驻留远端（loadScript no-op，经 ABI 调用）');
  }

  @override
  Future<void> loadLibrary(String script) async {}

  @override
  Future<void> loadScriptFromURL(String urlString) async {
    onLog?.call('Node 桥：远端进程常驻（loadScriptFromURL no-op）');
  }

  @override
  Future<void> registerSpider() async {
    _ready = true;
    onLog?.call('Node 桥：registerSpider → ready（远端进程常驻）');
  }

  @override
  bool get isSpiderReady => _ready;

  // ─────────────── 5 个操作 ───────────────

  @override
  Future<HomeContentResult> callHomeContent() => _call<HomeContentResult>(
        op: 'homeContent',
        params: const <String, Object?>{},
        parse: HomeContentResult.fromJson,
      );

  @override
  Future<SearchContentResult> callSearchContent(String keyword, int pg) =>
      _call<SearchContentResult>(
        op: 'searchContent',
        params: <String, Object?>{
          'keyword': keyword,
          'pg': pg,
        },
        parse: SearchContentResult.fromJson,
      );

  @override
  Future<CategoryContentResult> callCategoryContent(
          String tid, int pg, String extend) =>
      _call<CategoryContentResult>(
        op: 'categoryContent',
        params: <String, Object?>{
          'tid': tid,
          'pg': pg,
          'extend': extend,
        },
        parse: CategoryContentResult.fromJson,
      );

  @override
  Future<DetailContentResult> callDetailContent(String ids) =>
      _call<DetailContentResult>(
        op: 'detailContent',
        params: <String, Object?>{'ids': ids},
        parse: DetailContentResult.fromJson,
      );

  @override
  Future<PlayerContentResult> callPlayerContent(
          String vodId, String flag, String url) =>
      _call<PlayerContentResult>(
        op: 'playerContent',
        params: <String, Object?>{
          'vodId': vodId,
          'flag': flag,
          'url': url,
        },
        parse: PlayerContentResult.fromJson,
      );

  @override
  Future<void> dispose() async {
    await _client.close();
    _ready = false;
  }

  // ─────────────── 内部 ───────────────

  Future<T> _call<T>({
    required String op,
    required Map<String, Object?> params,
    required T Function(Map<String, Object?>) parse,
  }) async {
    final Map<String, Object?> req = _codec.encodeRequest(
      op,
      params,
      siteKey: siteKey,
      engineType: engineType.rawValue,
      baseUrl: baseUrl,
      requestId: requestId,
    );
    final String raw;
    try {
      raw = await _client.postJson('/spider/', jsonEncode(req));
    } on TimeoutException {
      throw SpiderException(SpiderErrorCode.timeout, '$op 超时（Node 桥）');
    } on SocketException {
      throw SpiderException(
        SpiderErrorCode.runtime,
        '$op 失败：本机 Node 进程不可达（$engineType）',
      );
    }
    final AbiResponse r = _codec.decodeResponse(raw);
    for (final String log in r.logs) {
      onLog?.call(log);
    }
    return parse(r.data ?? const <String, Object?>{});
  }
}
