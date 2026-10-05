import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vbox/data/datasources/local/prefs_manager.dart';
import 'package:vbox/data/datasources/remote/baidu_ibox_client.dart';
import 'package:vbox/platform/spider/spider_http_bridge.dart';

/// 假传输（离线；记录请求便于断言 Cookie 语义）。
class _FakeTransport implements SpiderHttpTransport {
  _FakeTransport(this.handler);

  final SpiderTransportResponse Function(SpiderTransportRequest request) handler;
  final List<SpiderTransportRequest> requests = <SpiderTransportRequest>[];

  @override
  Future<SpiderTransportResponse> send(SpiderTransportRequest request) async {
    requests.add(request);
    return handler(request);
  }
}

SpiderTransportResponse _res(
  String body, {
  List<String> cookies = const <String>[],
}) =>
    SpiderTransportResponse(
      status: 200,
      headers: const <String, String>{},
      bodyBytes: utf8.encode(body),
      setCookies: cookies,
    );

/// 默认响应链（wap/init → verify → 桌面页 → templatevariable → share/list）。
SpiderTransportResponse _route(SpiderTransportRequest r) {
  final String url = r.url.toString();
  if (url.contains('/wap/init')) {
    return _res(
      '<html><script>yunData.FILEINFO = ['
      '{"fs_id":"111","server_filename":"EP01.mp4","isdir":"0"}'
      '];</script></html>',
      cookies: <String>['BAIDUID=abc; Path=/'],
    );
  }
  if (url.contains('/share/verify')) {
    return _res(
      '{"errno":0,"randsk":"rnd%2Fsk"}',
      cookies: <String>['BDCLND=rnd%2Fsk; Path=/'],
    );
  }
  if (url.contains('/api/gettemplatevariable')) {
    return _res('{"bdstoken":"tok123","shareid":"777","share_uk":"888"}');
  }
  if (url.contains('/share/list')) {
    if (url.contains('root=1')) {
      return _res(
        '{"errno":0,"data":{"share_id":"777","uk":"888","list":['
        '{"fs_id":"222","server_filename":"EP02.mp4","isdir":"0"},'
        '{"fs_id":"333","server_filename":"Season1","isdir":"1","path":"/Season1"}'
        ']}}',
      );
    }
    return _res(
      '{"errno":0,"data":{"list":['
      '{"fs_id":"444","server_filename":"EP03.mkv","isdir":"0"}'
      ']}}',
    );
  }
  return _res('{}');
}

void main() {
  group('百度 iBox 工具（对齐 iOS 同名函数）', () {
    test('parseToken：完整 Cookie（含 BDUSS/STOKEN）→ 原样规范化', () {
      final ({String bduss, String cookie}) r =
          BaiduIBoxClient.parseToken('Cookie: BDUSS=abc\r\nSTOKEN=st;   BAIDUID=b');
      expect(r.bduss, 'abc');
      expect(r.cookie, 'BDUSS=abc; STOKEN=st;   BAIDUID=b');
      expect(r.cookie.contains('\r'), isFalse);
    });

    test('parseToken：BDUSS|STOKEN 竖线形态 → 合成 Cookie', () {
      final ({String bduss, String cookie}) r =
          BaiduIBoxClient.parseToken('abc|STOKEN=st');
      expect(r.bduss, 'abc');
      expect(r.cookie, 'BDUSS=abc; STOKEN=st');
    });

    test('parseToken：裸 BDUSS → BDUSS= 前缀', () {
      expect(BaiduIBoxClient.parseToken('abc').cookie, 'BDUSS=abc');
    });

    test('mergeCookieStrings：忽略属性名 + 后到覆盖', () {
      final String merged = BaiduIBoxClient.mergeCookieStrings(<String>[
        'BDUSS=old; Path=/; Expires=Wed',
        'BDUSS=new; STOKEN=st; Secure',
      ]);
      expect(merged, 'BDUSS=new; STOKEN=st');
    });

    test('errorMessage：关键 errno 文案', () {
      expect(BaiduIBoxClient.errorMessage(-9), '提取码错误');
      expect(BaiduIBoxClient.errorMessage(200025), contains('分享验证态未绑定'));
      expect(BaiduIBoxClient.errorMessage(5), contains('分享链接不存在'));
    });

    test('extractSurl / extractPwd：保留前导 1 与提取码', () {
      expect(
        BaiduIBoxClient.extractSurl('https://pan.baidu.com/s/1abc?pwd=1234'),
        '1abc',
      );
      expect(
        BaiduIBoxClient.extractPwd('https://pan.baidu.com/s/1abc?pwd=1234'),
        '1234',
      );
      expect(BaiduIBoxClient.shortSurl('1abc'), 'abc');
    });
  });

  group('百度 iBox 分享链（C1）', () {
    late PrefsManager prefs;
    late _FakeTransport transport;
    late BaiduIBoxClient client;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      prefs = PrefsManager.instance;
      await prefs.init();
      await prefs.clearAll();
      transport = _FakeTransport(_route);
      client = BaiduIBoxClient(transport: transport, prefs: prefs);
    });

    test('extractShareMeta：多文件选集（yunData + root + 子目录）', () async {
      final BaiduShareMeta meta = await client.extractShareMeta(
        shareUrl: 'https://pan.baidu.com/s/1abc?pwd=1234',
        cookie: 'BDUSS=u',
        returnAll: true,
      );
      expect(meta.shareid, '777');
      expect(meta.shareUk, '888');
      expect(meta.bdstoken, 'tok123');
      expect(meta.randsk, 'rnd/sk');
      expect(meta.files.map((BaiduFileItem f) => f.name),
          <String>['EP01.mp4', 'EP02.mp4', 'EP03.mkv']);
      expect(meta.cookie.contains('BDCLND='), isTrue);
    });

    test('share/verify 必须不带 Cookie（对齐 iOS）', () async {
      await client.extractShareMeta(
        shareUrl: 'https://pan.baidu.com/s/1abc?pwd=1234',
        cookie: 'BDUSS=u',
        returnAll: true,
      );
      final SpiderTransportRequest verify = transport.requests
          .firstWhere((SpiderTransportRequest r) =>
              r.url.toString().contains('/share/verify'));
      expect(verify.headers['Cookie'], '');
      expect(verify.method, 'POST');
      expect(verify.body, contains('pwd=1234'));
    });

    test('root-shorturl 不带账号态 Cookie；dir 列举带账号态', () async {
      await client.extractShareMeta(
        shareUrl: 'https://pan.baidu.com/s/1abc?pwd=1234',
        cookie: 'BDUSS=u; STOKEN=st',
        returnAll: true,
      );
      final SpiderTransportRequest root = transport.requests.firstWhere(
          (SpiderTransportRequest r) =>
              r.url.toString().contains('root=1'));
      expect(root.headers['Cookie']!.contains('BDUSS'), isFalse);
      expect(root.headers['Cookie']!.contains('STOKEN'), isFalse);
      final SpiderTransportRequest dir = transport.requests.firstWhere(
          (SpiderTransportRequest r) =>
              r.url.toString().contains('is_from_web=true'));
      expect(dir.headers['Cookie']!.contains('BDUSS=u'), isTrue);
    });

    test('分享上下文缓存：二次调用命中缓存不再请求', () async {
      await client.extractShareMeta(
        shareUrl: 'https://pan.baidu.com/s/1abc?pwd=1234',
        cookie: 'BDUSS=u',
      );
      final int after = transport.requests.length;
      final BaiduShareMeta again = await client.extractShareMeta(
        shareUrl: 'https://pan.baidu.com/s/1abc?pwd=1234',
        cookie: 'BDUSS=u',
      );
      expect(transport.requests.length, after);
      expect(again.files, isNotEmpty);
      expect(
        await prefs.getString(BaiduIBoxClient.shareContextCacheKey),
        isNotEmpty,
      );
    });

    test('未拿到 shareid/uk → 明确报错', () async {
      final BaiduIBoxClient bad = BaiduIBoxClient(
        transport: _FakeTransport((SpiderTransportRequest r) =>
            _res('{"errno":0,"data":{"list":[]}}')),
        prefs: prefs,
      );
      await expectLater(
        bad.extractShareMeta(
          shareUrl: 'https://pan.baidu.com/s/1abc',
          cookie: 'BDUSS=u',
          returnAll: true,
        ),
        throwsA(isA<BaiduIBoxException>()),
      );
    });
  });
}