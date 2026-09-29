import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'node_project.dart';

/// Service for managing the embedded Node.js CatVod spider engine.
///
/// Talks to the native NodeBridge via MethodChannel (start/stop), then to the
/// spider HTTP API over 127.0.0.1:<port>. The spider server implements the
/// CatVod routes (/spider/3/<siteKey>...) plus the /api/* helper routes.
class NodeService with ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('com.example.tvs/node_bridge');

  static const int _defaultPort = 9775;
  static const int _defaultDartPort = 9776;

  bool _isRunning = false;
  int _port = 0;
  int _dartPort = 0;
  String? _error;
  DateTime? _lastStarted;
  bool _starting = false;

  bool get isRunning => _isRunning;
  int get port => _port;
  int get dartPort => _dartPort;
  String? get error => _error;
  DateTime? get lastStarted => _lastStarted;
  bool get isStarting => _starting;

  NodeService() {
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final running =
          await _channel.invokeMethod<bool>('isRunning') ?? false;
      _isRunning = running;
      if (running) {
        _port = await _channel.invokeMethod<int>('getNodePort') ?? _defaultPort;
        _dartPort = await _channel.invokeMethod<int>('getDartPort') ?? 9776;
      }
      notifyListeners();
    } catch (_) {
      _isRunning = false;
    }
  }

  /// 启动 spider 引擎。
  ///
  /// [bundlePath] 传的是 **bundle 文件名**（如 `catpaw_index.js`）。
  /// 真正的 JS 铺文件与占位符替换在 [NodeProject.stage] 里完成，
  /// 原生桥只接收铺好的工程目录并执行 node。
  Future<int?> startNode(String bundlePath) async {
    if (_isRunning || _starting) return _isRunning ? _port : null;
    _starting = true;
    _error = null;
    notifyListeners();

    try {
      final String nodeDir = await NodeProject.stage(
        bundle: bundlePath,
        port: _defaultPort,
        dartPort: _defaultDartPort,
      );
      final port = await _channel
          .invokeMethod<int>('startNode', {'nodeDir': nodeDir});
      if (port != null && port > 0) {
        _isRunning = true;
        _port = port;
        _dartPort = await _channel.invokeMethod<int>('getDartPort') ?? 9776;
        _lastStarted = DateTime.now();
      } else {
        _isRunning = false;
        _error = 'Node.js engine did not start';
      }
    } catch (e) {
      _isRunning = false;
      _error = e.toString();
    } finally {
      _starting = false;
      notifyListeners();
    }
    return _port;
  }

  Future<void> stopNode() async {
    try {
      await _channel.invokeMethod('stopNode');
    } catch (_) {}
    _isRunning = false;
    _port = 0;
    _lastStarted = null;
    notifyListeners();
  }

  Future<int?> restartNode(String bundlePath) async {
    await stopNode();
    return startNode(bundlePath);
  }

  /// Probe the spider API health endpoint.
  Future<bool> isHealthy() async {
    if (!_isRunning) return false;
    try {
      final result =
          await apiCall('/api/health', timeoutMs: 3000);
      return result['running'] == true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // HTTP API helpers (same shape as the Node spider server in node/spider/)
  // ------------------------------------------------------------------

  Future<Map<String, dynamic>> apiCall(
    String path, {
    Map<String, String>? params,
    String method = 'GET',
    Map<String, dynamic>? body,
    int timeoutMs = 15000,
  }) async {
    if (!_isRunning && path != '/api/health') {
      throw Exception('Node.js engine is not running');
    }

    var uri = Uri.http('127.0.0.1', path, params ?? {});
    if (uri.port == 0) uri = uri.replace(port: _port);
    final target =
        Uri.parse('http://127.0.0.1:${_port == 0 ? _defaultPort : _port}$path')
            .replace(queryParameters: params ?? {});

    final client = HttpClient()..connectionTimeout = Duration(milliseconds: timeoutMs);
    try {
      final request =
          await client.openUrl(method, target).timeout(Duration(milliseconds: timeoutMs));
      request.headers.contentType = ContentType.json;
      if (body != null) {
        request.write(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(responseBody);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'raw': decoded};
      }
      throw Exception('API ${response.statusCode}: $path');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('API error on $path: $e');
    } finally {
      client.close(force: true);
    }
  }

  /// CatVod spider routes use /spider/3/<siteKey>/... ; home data:
  /// GET /spider/3/<siteKey> (JSON config with sites list).
  Future<List<VodSite>> getSites() async {
    try {
      final result = await apiCall('/spider/3/spider-config');
      final list = result['list'] as List<dynamic>?;
      if (list == null) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(VodSite.fromJson)
          .toList();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  /// Search across spider sites.
  Future<List<Vod>> searchVideos(
    String keyword, {
    String? siteKey,
  }) async {
    final params = <String, String>{'wd': keyword};
    if (siteKey != null) params['siteKey'] = siteKey;
    try {
      final result = await apiCall('/api/search', params: params);
      final list = result['list'] as List<dynamic>? ?? [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(Vod.fromJson)
          .toList();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  /// Home page recommendations from a site.
  Future<List<Vod>> getHomeVideos({String? siteKey}) async {
    final path = siteKey == null ? '/api/home' : '/spider/3/$siteKey';
    try {
      final result = await apiCall(path);
      final list = result['list'] as List<dynamic>? ?? [];
      return list.whereType<Map<String, dynamic>>().map(Vod.fromJson).toList();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  Future<List<Vod>> getHotVideos() async {
    try {
      final result = await apiCall('/api/hot');
      final list = result['list'] as List<dynamic>? ?? [];
      return list.whereType<Map<String, dynamic>>().map(Vod.fromJson).toList();
    } catch (e) {
      return [];
    }
  }

  /// Video detail (play sources included).
  Future<Map<String, dynamic>> getVideoDetail(
    String siteKey,
    String vodId,
  ) async {
    return apiCall('/detail/$siteKey/$vodId');
  }

  /// Resolve a playable URL for a specific source/episode.
  Future<String?> getPlayUrl(
    String siteKey,
    String vodId, {
    String? playFrom,
  }) async {
    try {
      final params = <String, String>{'siteKey': siteKey, 'vodId': vodId};
      if (playFrom != null) params['playFrom'] = playFrom;
      final result = await apiCall('/api/play', params: params);
      return result['url'] as String?;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<List<LiveSource>> getLiveSources() async {
    try {
      final result = await apiCall('/api/live');
      final list = result['list'] as List<dynamic>? ?? [];
      return list.whereType<Map<String, dynamic>>().map(LiveSource.fromJson).toList();
    } catch (e) {
      return [];
    }
  }

  /// Read the spider config (db.json mirror exposed by the API).
  Future<Map<String, dynamic>> getConfig() async {
    return apiCall('/api/config');
  }

  /// Push an updated config into the spider engine.
  Future<bool> saveConfig(Map<String, dynamic> config) async {
    try {
      await apiCall('/api/config', method: 'POST', body: config);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── Website API convenience wrappers ──────────────────────
  // 对应 bundle 中的 /website/* 路由族。

  Future<http.Response> get(String path,
      {Map<String, String>? params}) async {
    final target = _buildUri(path, params);
    final client = http.Client();
    try {
      return await client.get(target).timeout(const Duration(seconds: 10));
    } finally {
      client.close();
    }
  }

  Future<http.Response> post(String path,
      {Map<String, String>? params, Object? body}) async {
    final target = _buildUri(path, params);
    final client = http.Client();
    try {
      return await client
          .post(target, body: body is String ? body : jsonEncode(body))
          .timeout(const Duration(seconds: 10));
    } finally {
      client.close();
    }
  }

  Future<http.Response> put(String path,
      {Map<String, String>? params, Object? body}) async {
    final target = _buildUri(path, params);
    final client = http.Client();
    try {
      return await client
          .put(target, body: body is String ? body : jsonEncode(body))
          .timeout(const Duration(seconds: 10));
    } finally {
      client.close();
    }
  }

  Future<http.Response> delete(String path,
      {Map<String, String>? params, Object? body}) async {
    final target = _buildUri(path, params);
    final client = http.Client();
    try {
      return await client
          .delete(target, body: body is String ? body : jsonEncode(body))
          .timeout(const Duration(seconds: 10));
    } finally {
      client.close();
    }
  }

  Uri _buildUri(String path, Map<String, String>? params) {
    final port = _port == 0 ? _defaultPort : _port;
    return Uri.parse('http://127.0.0.1:$port$path')
        .replace(queryParameters: params ?? {});
  }
}
