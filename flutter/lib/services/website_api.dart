import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'node_service.dart';

/// Website 设置中心 API 客户端。
/// 对应 bundle 中的 `/website/*` 路由族。
class WebsiteApiService with ChangeNotifier {
  final NodeService _node;
  WebsiteApiService(this._node);

  // ── 状态 ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> status() async {
    final r = await _node.get('/website/api/status');
    return jsonDecode(r.body);
  }

  // ── 站源管理 ──────────────────────────────────────────────
  Future<Map<String, dynamic>> getSites() async {
    final r = await _node.get('/website/api/sites');
    return jsonDecode(r.body);
  }

  Future<void> setSites(List sites) async {
    await _node.put('/website/api/sites',
        body: jsonEncode({'list': sites}));
  }

  Future<void> deleteSites() async {
    await _node.delete('/website/api/sites');
  }

  // ── 凭据管理（14 个 Provider） ─────────────────────────────
  Future<Map<String, dynamic>> getCredentials() async {
    final r = await _node.get('/website/api/credentials');
    return jsonDecode(r.body);
  }

  Future<void> setCredential(String provider, String field, String value) async {
    await _node.put('/website/api/credential/$provider/$field',
        body: jsonEncode({'value': value}));
  }

  Future<void> deleteCredential(String provider, String field) async {
    await _node.delete('/website/api/credential/$provider/$field');
  }

  // ── 扫码登录 ──────────────────────────────────────────────
  Future<Map<String, dynamic>> loginStart(String provider) async {
    final r = await _node.post('/website/api/login/start',
        body: jsonEncode({'provider': provider}));
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> loginPoll(String provider, String taskId) async {
    final r = await _node.post('/website/api/login/poll',
        body: jsonEncode({'provider': provider, 'taskId': taskId}));
    return jsonDecode(r.body);
  }

  Future<void> loginCancel(String taskId) async {
    await _node.post('/website/api/login/cancel',
        body: jsonEncode({'taskId': taskId}));
  }

  // ── B 站扫码 ──────────────────────────────────────────────
  Future<Map<String, dynamic>> biliLoginStart() async {
    final r = await _node.post('/website/api/bili/login/start');
    return jsonDecode(r.body);
  }

  // ── Emby ──────────────────────────────────────────────────
  Future<void> embyAdd(Map server) async {
    await _node.post('/website/api/emby', body: jsonEncode(server));
  }

  Future<void> embyTest(int index) async {
    await _node.post('/website/api/emby/test',
        body: jsonEncode({'index': index}));
  }

  Future<void> embyDelete(int index) async {
    await _node.delete('/website/api/emby/$index');
  }

  // ── 直播转点播 ────────────────────────────────────────────
  Future<String> getLiveToVodUrl() async {
    final r = await _node.get('/website/api/livetovod/url');
    final data = jsonDecode(r.body);
    return (data['data'] ?? '').toString();
  }

  Future<void> setLiveToVodUrl(String url) async {
    await _node.put('/website/api/livetovod/url',
        body: jsonEncode({'url': url}));
  }

  // ── 远程配置 ──────────────────────────────────────────────
  Future<Map<String, dynamic>> getRemoteWex() async {
    final r = await _node.get('/website/api/remote-wex');
    return jsonDecode(r.body);
  }

  // ── 弹幕设置 ──────────────────────────────────────────────
  Future<Map<String, dynamic>> getDanmuSetting() async {
    final r = await _node.get('/website/danmu/setting');
    return jsonDecode(r.body);
  }

  Future<void> pushDanmu(List items) async {
    await _node.post('/website/danmu/push',
        body: jsonEncode(items));
  }
}