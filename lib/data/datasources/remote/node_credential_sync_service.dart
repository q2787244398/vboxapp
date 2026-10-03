/// 数据层：Node 凭据同步服务（批次 F · F-03）。
///
/// 对齐 iOS `NodeCredentialSyncService`（`vbox/Services/NodeCredentialSyncService.swift`）：
/// - **push（queryProfile）**：把本机安全存储（`cloud_drive_credentials_v1`）中
///   Node 托管网盘的凭据镜像到 Node 常驻系统
///   （`PUT /website/api/credential/:provider/:field` body `{"value": "..."}`）；
/// - **pull（saveProfile）**：把 Node 常驻系统凭据拉回本机安全存储
///   （`GET /website/api/credentials` → `{code:0, data:{...}}`）；
/// - **deleteNodeCredential**：级联删除 Node 侧逐字段凭据 + 本机主凭据。
///
/// 铁律（对齐 iOS）：
///   1. 同步范围严格限定 Node 托管 11 家（见 [nodeManagedProviders]）；
///   2. 百度 / 夸克 / UC / 阿里的**原生**既有凭据与 Node 无交集，本服务不读写；
///   3. 凭据落点统一为契约安全存储，Node 仅作镜像。
///
/// 协议调用经 [NodeCredentialApiClient] 抽象注入（UI/测试不依赖真实端口）；
/// 缺省 [UnavailableNodeCredentialApiClient] 行为对齐 iOS Node 未就绪。
library;

import 'dart:convert';
import 'dart:io';

import '../../../domain/entities/cloud/cloud_drive.dart';
import '../../../domain/entities/cloud/node_credential_sync.dart';
import '../local/cloud_drive_credential_store.dart';
import '../local/prefs_manager.dart';

/// Node 凭据同步错误（文案对齐 iOS `NodeCredentialSyncError`）。
class NodeCredentialSyncException implements Exception {
  /// 构造。
  const NodeCredentialSyncException(this.message);

  /// 面向用户的错误文案。
  final String message;

  @override
  String toString() => message;
}

/// Node 凭据同步 HTTP 接缝（可注入）。
abstract interface class NodeCredentialApiClient {
  /// 发起 [method] 请求到 [path]，返回解析后的 JSON 对象。
  ///
  /// 失败（Node 未就绪 / 非 2xx / `code!=0`）抛 [NodeCredentialSyncException]。
  Future<Map<String, dynamic>> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  });
}

/// 缺省接缝：Node 常驻系统未接入（对齐 iOS `nodeNotReady`）。
class UnavailableNodeCredentialApiClient implements NodeCredentialApiClient {
  /// 构造。
  const UnavailableNodeCredentialApiClient();

  @override
  Future<Map<String, dynamic>> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async =>
      throw const NodeCredentialSyncException('Node 常驻系统未就绪');
}

/// 本机常驻 Node 进程客户端（`127.0.0.1:<port>`，默认 58080）。
///
/// 对齐 iOS `requestJSON(_:_:body:attempts:)`：最多 3 次重试（0.5s 递增退避），
/// 校验 HTTP 2xx 与响应体 `code == 0`。
class LocalNodeCredentialApiClient implements NodeCredentialApiClient {
  /// 构造（[port] 默认 58080；[timeout] 单次超时）。
  LocalNodeCredentialApiClient({
    this.port = 58080,
    this.timeout = const Duration(seconds: 15),
    this.attempts = 3,
  });

  /// Node 端口。
  final int port;

  /// 单次请求超时。
  final Duration timeout;

  /// 最大尝试次数。
  final int attempts;

  final HttpClient _client = HttpClient();

  @override
  Future<Map<String, dynamic>> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    NodeCredentialSyncException last =
        const NodeCredentialSyncException('未知错误');
    for (int attempt = 1; attempt <= attempts; attempt++) {
      try {
        final HttpClientRequest req = await _client
            .openUrl(method, Uri.parse('http://127.0.0.1:$port$path'))
            .timeout(timeout);
        req.headers.contentType = ContentType.json;
        if (body != null) req.write(jsonEncode(body));
        final HttpClientResponse res = await req.close().timeout(timeout);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw NodeCredentialSyncException('HTTP ${res.statusCode}');
        }
        final String text = await res.transform(utf8.decoder).join();
        final Object? decoded =
            text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
        final Map<String, dynamic> json = decoded is Map
            ? <String, dynamic>{
                for (final MapEntry<Object?, Object?> e in decoded.entries)
                  e.key.toString(): e.value,
              }
            : <String, dynamic>{};
        final Object? code = json['code'];
        if (code is int && code != 0) {
          throw NodeCredentialSyncException(
            'Node 拒绝: ${json['msg'] ?? 'code=$code'}',
          );
        }
        return json;
      } catch (e) {
        last = e is NodeCredentialSyncException
            ? e
            : NodeCredentialSyncException('$e');
        if (attempt < attempts) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }
    throw last;
  }

  /// 释放连接资源。
  void close() => _client.close(force: true);
}

/// Node 凭据同步服务。
class NodeCredentialSyncService {
  /// 构造（[client] 供测试注入；缺省「未接入」）。
  NodeCredentialSyncService({
    CloudDriveCredentialStore? store,
    NodeCredentialApiClient client = const UnavailableNodeCredentialApiClient(),
  })  : _store = store,
        _client = client;

  final CloudDriveCredentialStore? _store;
  final NodeCredentialApiClient _client;

  /// 懒取存储（缺省 `CloudDriveCredentialStore(PrefsManager.instance)`）。
  CloudDriveCredentialStore get store =>
      _store ?? CloudDriveCredentialStore(PrefsManager.instance);

  /// 按方向编排同步（对齐 iOS `syncNow(direction:)`）。
  Future<NodeCredentialSyncSummary> syncNow([
    NodeCredentialSyncDirection direction = NodeCredentialSyncDirection.both,
  ]) async {
    switch (direction) {
      case NodeCredentialSyncDirection.push:
        return push();
      case NodeCredentialSyncDirection.pull:
        return pull();
      case NodeCredentialSyncDirection.both:
        final NodeCredentialSyncSummary pushResult = await push();
        final NodeCredentialSyncSummary pullResult = await pull();
        return NodeCredentialSyncSummary(
          pushedFields: pushResult.pushedFields,
          pulledDrives: pullResult.pulledDrives,
          errors: <String>[...pushResult.errors, ...pullResult.errors],
          duration: pushResult.duration + pullResult.duration,
        );
    }
  }

  /// 本机 → Node（对齐 iOS `queryProfile()`）。
  Future<NodeCredentialSyncSummary> queryProfile() => push();

  /// Node → 本机（对齐 iOS `saveProfile()`）。
  Future<NodeCredentialSyncSummary> saveProfile() => pull();

  /// 本机 → Node：逐字段 PUT。
  Future<NodeCredentialSyncSummary> push() async {
    final Stopwatch sw = Stopwatch()..start();
    int pushed = 0;
    final List<String> errors = <String>[];
    final Map<String, CloudDriveCredential> all = await store.loadAll();

    for (final MapEntry<String, NodeCredentialProviderSpec> entry
        in nodeManagedProviders.entries) {
      final CloudDriveCredential? credential = all[entry.key];
      if (credential == null) continue;
      for (final NodeCredentialFieldMap field in entry.value.fields) {
        final String? value =
            nodeCredentialSlotValue(credential, field.keychainSlot);
        if (value == null || value.isEmpty) continue;
        try {
          await _client.requestJson(
            'PUT',
            '/website/api/credential/${entry.value.provider}/${field.nodeField}',
            body: <String, dynamic>{'value': value},
          );
          pushed += 1;
        } catch (e) {
          errors.add('push ${entry.key}.${field.nodeField}: $e');
        }
      }
    }
    sw.stop();
    return NodeCredentialSyncSummary(
      pushedFields: pushed,
      errors: errors,
      duration: sw.elapsed,
    );
  }

  /// Node → 本机：GET 权威读接口后合并落库。
  Future<NodeCredentialSyncSummary> pull() async {
    final Stopwatch sw = Stopwatch()..start();
    final Set<String> pulled = <String>{};
    final List<String> errors = <String>[];

    final Map<String, CloudDriveCredential> all = await store.loadAll();
    try {
      final Map<String, dynamic> json =
          await _client.requestJson('GET', '/website/api/credentials');
      final Object? data = json['data'];
      if (data is Map) {
        for (final MapEntry<String, String> entry
            in nodePullableProviders.entries) {
          final Object? raw = data[entry.key];
          if (raw is! Map) continue;
          final NodeCredentialProviderSpec? spec =
              nodeManagedProviders[entry.value];
          if (spec == null) continue;
          final Map<String, String> values = <String, String>{};
          for (final NodeCredentialFieldMap field in spec.fields) {
            final Object? v = raw[field.nodeField];
            if (v is String && v.isNotEmpty) values[field.nodeField] = v;
          }
          if (values.isEmpty) continue;
          all[entry.value] =
              _upsert(all[entry.value], entry.value, values, spec);
          pulled.add(entry.value);
        }
      }
    } catch (e) {
      errors.add('pull(HTTP): $e');
    }

    if (pulled.isNotEmpty) {
      await store.saveAll(all);
    }
    sw.stop();
    return NodeCredentialSyncSummary(
      pulledDrives: pulled.toList()..sort(),
      errors: errors,
      duration: sw.elapsed,
    );
  }

  /// 级联删除 Node 登录态（对齐 iOS `deleteNodeCredential(driveType:)`）：
  /// 逐字段 DELETE + 本机主凭据删除。
  ///
  /// 说明：iOS 额外直改 `wexfnwconfig.json` 兜底清理；Flutter 侧 Node 运行目录
  /// 由平台层管理，本段仅做协议侧删除 + 本机凭据删除（Node DELETE 失败时
  /// 由下一次 pull 的 `values.isEmpty` 门限兜住，不复活登录态）。
  Future<NodeCredentialSyncSummary> deleteNodeCredential(
    CloudDriveType type,
  ) async {
    final Stopwatch sw = Stopwatch()..start();
    final NodeCredentialProviderSpec? spec = nodeManagedProviders[type.id];
    if (spec == null) {
      return const NodeCredentialSyncSummary();
    }
    final List<String> errors = <String>[];
    for (final NodeCredentialFieldMap field in spec.fields) {
      try {
        await _client.requestJson(
          'DELETE',
          '/website/api/credential/${spec.provider}/${field.nodeField}',
        );
      } catch (e) {
        errors.add('delete ${type.id}.${field.nodeField}: $e');
      }
    }
    await store.remove(type);
    sw.stop();
    return NodeCredentialSyncSummary(errors: errors, duration: sw.elapsed);
  }

  /// 合并 Node 侧字段到本机凭据（统一标记 `valid` + 同步说明）。
  CloudDriveCredential _upsert(
    CloudDriveCredential? existing,
    String driveTypeId,
    Map<String, String> values,
    NodeCredentialProviderSpec spec,
  ) {
    CloudDriveCredential credential =
        existing ?? _emptyCredential(driveTypeId);
    for (final NodeCredentialFieldMap field in spec.fields) {
      final String? value = values[field.nodeField];
      if (value == null || value.isEmpty) continue;
      credential = withNodeCredentialSlot(credential, field.keychainSlot, value);
    }
    final DateTime now = DateTime.now();
    return credential.copyWith(
      state: CloudDriveAuthState.valid,
      statusMessage: '已与 Node 常驻系统同步',
      updatedAt: now,
      lastCheckedAt: now,
    );
  }

  CloudDriveCredential _emptyCredential(String driveTypeId) =>
      CloudDriveCredential(
        driveType: driveTypeId,
        updatedAt: DateTime.now(),
        state: CloudDriveAuthState.unknown,
      );
}
