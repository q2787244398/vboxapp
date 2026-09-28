import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App configuration, persisted in SharedPreferences.
///
/// The original app stored some settings natively via ConfigCenterActivity;
/// this reconstruction keeps the same surface (API host, spider bundle,
/// player & network options) but backings it with portable prefs so all
/// three desktop/mobile targets share one implementation.
class ConfigService with ChangeNotifier {
  static const String _storeKey = 'tvs_config';

  SharedPreferences? _prefs;

  Map<String, dynamic> _config = {
    'apiHost': 'http://127.0.0.1:9775',
    'spiderBundle': 'spider.js',
    'playEngine': 'yl_player',
    'autoPlay': true,
    'showCover': true,
    'hwDecoder': true,
    'bufferMs': 2000,
    'enableProxy': false,
    'proxyUrl': '',
    'defaultSite': '',
    'defaultPlayFrom': '',
    'playHistoryLimit': 100,
    'enableDanmu': false,
    'enableDebug': false,
    'maxConcurrentVideos': 3,
  };

  Map<String, dynamic> get config => Map.unmodifiable(_config);
  bool get isReady => _prefs != null;

  ConfigService() {
    _load();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_storeKey);
    if (raw != null) {
      try {
        _config.addAll(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
    notifyListeners();
  }

  T? getValue<T>(String key, [T? defaultValue]) {
    final v = _config[key];
    if (v is T) return v;
    return defaultValue;
  }

  Future<void> setValue(String key, dynamic value) async {
    _config[key] = value;
    await _persist();
  }

  Future<void> _persist() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_storeKey, jsonEncode(_config));
    notifyListeners();
  }

  Future<void> reset() async {
    _config = {
      'apiHost': 'http://127.0.0.1:9775',
      'spiderBundle': 'spider.js',
      'playEngine': 'yl_player',
      'autoPlay': true,
      'showCover': true,
      'hwDecoder': true,
      'bufferMs': 2000,
      'enableProxy': false,
      'proxyUrl': '',
      'defaultSite': '',
      'defaultPlayFrom': '',
      'playHistoryLimit': 100,
      'enableDanmu': false,
      'enableDebug': false,
      'maxConcurrentVideos': 3,
    };
    await _persist();
  }

  Future<String> exportConfig() async {
    return jsonEncode(_config);
  }

  Future<bool> importConfig(String json) async {
    try {
      final map = jsonDecode(json);
      if (map is Map<String, dynamic>) {
        _config.addAll(map);
        await _persist();
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ----- convenience getters -----
  String get apiHost => getValue('apiHost', 'http://127.0.0.1:9775')!;
  String get spiderBundle => getValue('spiderBundle', 'spider.js')!;
  bool get autoPlay => getValue('autoPlay', true)!;
  bool get showCover => getValue('showCover', true)!;
  bool get hwDecoder => getValue('hwDecoder', true)!;
  int get bufferMs => getValue('bufferMs', 2000)!;
  bool get enableProxy => getValue('enableProxy', false)!;
  String get proxyUrl => getValue('proxyUrl', '')!;
  String get defaultSite => getValue('defaultSite', '')!;
  String get defaultPlayFrom => getValue('defaultPlayFrom', '')!;
  int get playHistoryLimit => getValue('playHistoryLimit', 100)!;
  bool get enableDanmu => getValue('enableDanmu', false)!;
  bool get enableDebug => getValue('enableDebug', false)!;
  int get maxConcurrentVideos => getValue('maxConcurrentVideos', 3)!;
}
