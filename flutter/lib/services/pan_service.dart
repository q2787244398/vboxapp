import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 14 个网盘 Provider 的 API 客户端。
/// 端点与鉴权方式来自逆向还原包 `pan-apis.md`。
class PanService with ChangeNotifier {

  // ── 115 云盘 ──────────────────────────────────────────────
  static const _y115Base = 'https://webapi.115.com';
  static const _y115Ua =
      'Mozilla/5.0 ... Chrome/125.0.0.0 Safari/537.36 115Browser/36.0.0 Chromium/125.0';

  Future<Map<String, dynamic>> y115List(String cookie,
      {required String cid}) async {
    final r = await http.get(
      Uri.parse('$_y115Base/files?aid=1&cid=$cid&o=user_ptime&show_dir=1&limit=115&format=json'),
      headers: {
        'Cookie': cookie,
        'Referer': 'https://webapi.115.com/bridge_2.0.html',
        'Origin': 'https://115.com',
        'User-Agent': _y115Ua,
      },
    );
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> y115Search(String cookie,
      {required String searchValue}) async {
    final r = await http.get(
      Uri.parse('$_y115Base/files/search?search_value=$searchValue&type=4&limit=20'),
      headers: {
        'Cookie': cookie,
        'Referer': 'https://webapi.115.com/bridge_2.0.html',
        'Origin': 'https://115.com',
        'User-Agent': _y115Ua,
      },
    );
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> y115Snap(String cookie,
      {required String shareCode, required String receiveCode}) async {
    final r = await http.get(
      Uri.parse('$_y115Base/share/snap?share_code=$shareCode&receive_code=$receiveCode'),
      headers: {
        'Cookie': cookie,
        'Referer': 'https://webapi.115.com/bridge_2.0.html',
        'Origin': 'https://115.com',
        'User-Agent': _y115Ua,
      },
    );
    return jsonDecode(r.body);
  }

  // ── 天翼云盘 189 ──────────────────────────────────────────
  static const _tianyiBase = 'https://api.cloud.189.cn/open/file';
  static const _tianyiHeaders = {
    'appId': '8025431004',
    'clientType': '10020',
    'appVersion': '6.2',
    'platform': 'web_cloud.189.cn',
  };

  Future<Map<String, dynamic>> tianyiDownloadUrl(String cookie,
      {required String fileId}) async {
    final r = await http.get(
      Uri.parse('$_tianyiBase/getFileDownloadUrl.action?fileId=$fileId'),
      headers: {..._tianyiHeaders, 'Cookie': cookie},
    );
    return jsonDecode(r.body);
  }

  // ── 123 云盘 ──────────────────────────────────────────────
  static const _pan123Base = 'https://open-api.123pan.com';

  Future<Map<String, dynamic>> pan123Login(
      String username, String password) async {
    final r = await http.post(
      Uri.parse('$_pan123Base/api/v1/user/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    return jsonDecode(r.body);
  }

  // ── 夸克 ──────────────────────────────────────────────────
  static const _quarkBase = 'https://pan.quark.cn';

  Future<Map<String, dynamic>> quarkList(String cookie) async {
    final r = await http.get(
      Uri.parse('$_quarkBase/api/v1/fs/list'),
      headers: {'Cookie': cookie},
    );
    return jsonDecode(r.body);
  }

  // ── UC ────────────────────────────────────────────────────
  static const _ucBase = 'https://api.open.uc.cn';

  Future<Map<String, dynamic>> ucDrive(String cookie, String token,
      {String? refreshToken}) async {
    final r = await http.get(
      Uri.parse('$_ucBase/drive/v1/list'),
      headers: {
        'Cookie': cookie,
        'Authorization': 'Bearer $token',
        if (refreshToken != null) 'X-Refresh-Token': refreshToken,
      },
    );
    return jsonDecode(r.body);
  }

  // ── 百度网盘 ──────────────────────────────────────────────
  static const _baiduBase = 'https://pan.baidu.com';

  Future<Map<String, dynamic>> baiduList(String cookie,
      {required String dir}) async {
    final r = await http.get(
      Uri.parse('$_baiduBase/api/v2/list?order=name&type=0&dir=$dir'),
      headers: {'Cookie': cookie},
    );
    return jsonDecode(r.body);
  }

  // ── 移动云盘 139 ──────────────────────────────────────────
  static const _new139Base = 'https://api.cloud.139.cn';
  static const _new139Fingerprint = {
    'brand': 'HONOR',
    'model': 'MAG-AN00',
    'os': 'android 13',
    'screen': '1200X2664',
    'appVersion': '13.1.0',
    'deviceId': '069A0369',
  };

  Future<Map<String, dynamic>> new139SmsSend(String phone) async {
    final r = await http.post(
      Uri.parse('$_new139Base/mobilenew/login/sms/send'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent':
            'android|MAG-AN00|android 13|mCloud13.1.0-000',
        ..._new139Fingerprint,
      },
      body: 'phone=$phone',
    );
    return jsonDecode(r.body);
  }

  // ── 迅雷 ──────────────────────────────────────────────────
  static const _xunleiBase = 'https://api-pan.xunlei.com';
  static const _xunleiFingerprint = {
    'authPackage': 'com.xunlei.downloadprovider',
    'authVersion': 'downloadprovider-25.0.6.30',
    'authClientId': 'Xp6vsxz_7IYVw2BB',
  };

  Future<Map<String, dynamic>> xunleiLogin(String phone, String captcha) async {
    final r = await http.post(
      Uri.parse('$_xunleiBase/user/login'),
      headers: {
        'Content-Type': 'application/json',
        ..._xunleiFingerprint,
      },
      body: jsonEncode({'phone': phone, 'captcha': captcha}),
    );
    return jsonDecode(r.body);
  }

  // ── B 站 ──────────────────────────────────────────────────
  static const _biliBase = 'https://api.bilibili.com';

  Future<Map<String, dynamic>> biliLoginStart() async {
    final r = await http.post(
      Uri.parse('$_biliBase/x/v2/login/qrcode/poll'),
      headers: {'User-Agent': 'BilibiliTVS'},
    );
    return jsonDecode(r.body);
  }

  // ── 光鸭 ──────────────────────────────────────────────────
  static const _guangyaBase = 'https://guangyapan.com';

  Future<Map<String, dynamic>> guangyaSmsSend(String phone) async {
    final r = await http.post(
      Uri.parse('$_guangyaBase/api/sms/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone}),
    );
    return jsonDecode(r.body);
  }

  // ── 蜗牛 woniu4k ──────────────────────────────────────────
  static const _woniuBase = 'https://woniu4k.com';

  Future<Map<String, dynamic>> woniuLogin(String username, String password) async {
    final r = await http.post(
      Uri.parse('$_woniuBase/api/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> woniuVerify(String token) async {
    final r = await http.post(
      Uri.parse('$_woniuBase/api/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token}),
    );
    return jsonDecode(r.body);
  }

  // ── Emby ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> embyTest(String serverUrl, String username,
      String password) async {
    final r = await http.post(
      Uri.parse('$serverUrl/Users/authenticate'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'MediaBrowser Client="TVS", Device="TVS"',
      },
      body: jsonEncode({'Username': username, 'Password': password}),
    );
    return jsonDecode(r.body);
  }

  // ── PikPak ────────────────────────────────────────────────
  static const _pikpakBase = 'https://api.pikpak.com';

  Future<Map<String, dynamic>> pikpakLogin(
      String username, String password) async {
    final r = await http.post(
      Uri.parse('$_pikpakBase/auth/v1/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'client_id': 'Ym9ja3NwYXRoOnVzZXI6...',
        'client_secret': 'Ym9ja3NwYXRoOnVzZXI6...',
      }),
    );
    return jsonDecode(r.body);
  }

  // ── 阿里云盘 ──────────────────────────────────────────────
  static const _aliBase = 'https://aliyundrive.com';

  Future<Map<String, dynamic>> aliList(String token) async {
    final r = await http.post(
      Uri.parse('$_aliBase/adrive/v1/file/list'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'drive_id': 'root', 'parent_file_id': 'root'}),
    );
    return jsonDecode(r.body);
  }
}