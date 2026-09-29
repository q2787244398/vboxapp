/// 核心层单测：HTTP 响应体解码链 + HTTP 客户端。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vbox/core/errors/exceptions.dart';
import 'package:vbox/core/network/http_body_decoder.dart';
import 'package:vbox/core/network/http_client.dart';
import 'package:vbox/core/utils/charset.dart';

void main() {
  setUp(() => registerCharsetTables(gbk: <int, String>{}, big5: <int, String>{}));

  group('decodeResponseBody（契约 §4.2）', () {
    test('① 响应头 charset 优先', () {
      final (String text, bool b64) = decodeResponseBody(
        Uint8List.fromList(utf8.encode('中文')),
        contentTypeCharset: 'utf-8',
      );
      expect(text, '中文');
      expect(b64, isFalse);
    });

    test('② UTF-8 直接成功', () {
      final (String text, bool b64) =
          decodeResponseBody(Uint8List.fromList(utf8.encode('hello 世界')));
      expect(text, 'hello 世界');
      expect(b64, isFalse);
    });

    test('② meta 声明非 UTF-8 时用 meta 重解（此处 ASCII 内容等价）', () {
      registerCharsetTables(gbk: <int, String>{0xC4E3: '你'});
      final (String text, bool b64) = decodeResponseBody(
        Uint8List.fromList('plain'.codeUnits),
        metaCharsetOverride: 'gbk',
      );
      expect(text, 'plain');
      expect(b64, isFalse);
    });

    test('③ meta 探测 + 码表解码多字节内容', () {
      registerCharsetTables(gbk: <int, String>{0xC4E3: '你'});
      final List<int> raw = <int>[
        ...'<meta charset="gbk">'.codeUnits,
        0xC4,
        0xE3,
      ];
      final (String text, bool b64) =
          decodeResponseBody(Uint8List.fromList(raw));
      expect(text.contains('你'), isTrue);
      expect(b64, isFalse);
    });

    test('④ 未注册码表 → 回退 latin1，且不触发 base64', () {
      final (String text, bool b64) =
          decodeResponseBody(Uint8List.fromList(<int>[0xC4, 0xE3]));
      expect(text, 'Äã');
      expect(b64, isFalse);
    });

    test('④ 注册码表后同一字节解出中文', () {
      registerCharsetTables(gbk: <int, String>{0xC4E3: '你'});
      final (String text, bool b64) =
          decodeResponseBody(Uint8List.fromList(<int>[0xC4, 0xE3]));
      expect(text, '你');
      expect(b64, isFalse);
    });

    test('兜底链顺序与契约一致', () {
      expect(kDecoderFallbackChain, <String>['gbk', 'gb2312', 'big5', 'latin1']);
    });
  });

  group('HttpClient', () {
    final Uri uri = Uri.parse('https://example.com/a.html');

    test('GET：注入 UA、解码文本、无兜底', () async {
      String? seenUa;
      final HttpClient client = HttpClient(
        inner: MockClient((http.Request req) async {
          seenUa = req.headers['user-agent'];
          return http.Response(
            '你好',
            200,
            headers: <String, String>{'content-type': 'text/html; charset=utf-8'},
          );
        }),
        retryBaseDelay: Duration.zero,
      );
      addTearDown(client.close);

      final HttpClientResponse res = await client.get(uri);
      expect(res.isOk, isTrue);
      expect(res.text, '你好');
      expect(res.usedBase64Fallback, isFalse);
      expect(res.byteLength, utf8.encode('你好').length);
      expect(seenUa, contains('Mozilla'));
    });

    test('POST 表单：编码与 content-type', () async {
      String? contentType;
      String? body;
      final HttpClient client = HttpClient(
        inner: MockClient((http.Request req) async {
          contentType = req.headers['content-type'];
          body = req.body;
          return http.Response('ok', 200);
        }),
        retryBaseDelay: Duration.zero,
      );
      addTearDown(client.close);

      await client.postForm(uri, <String, String>{'a': '1', 'b': 'x y'});
      expect(contentType, contains('application/x-www-form-urlencoded'));
      expect(body, 'a=1&b=x+y');
    });

    test('5xx 按退避重试直至成功', () async {
      int calls = 0;
      final HttpClient client = HttpClient(
        inner: MockClient((http.Request req) async {
          calls++;
          return calls < 3
              ? http.Response('err', 500)
              : http.Response('ok', 200);
        }),
        retryBaseDelay: Duration.zero,
        maxRetries: 2,
      );
      addTearDown(client.close);

      final HttpClientResponse res = await client.get(uri);
      expect(calls, 3);
      expect(res.text, 'ok');
    });

    test('5xx 用尽重试后返回响应本体（不抛异常）', () async {
      int calls = 0;
      final HttpClient client = HttpClient(
        inner: MockClient((http.Request req) async {
          calls++;
          return http.Response('err', 503);
        }),
        retryBaseDelay: Duration.zero,
        maxRetries: 1,
      );
      addTearDown(client.close);

      final HttpClientResponse res = await client.get(uri);
      expect(calls, 2);
      expect(res.statusCode, 503);
      expect(res.isOk, isFalse);
    });

    test('4xx 不重试', () async {
      int calls = 0;
      final HttpClient client = HttpClient(
        inner: MockClient((http.Request req) async {
          calls++;
          return http.Response('nope', 404);
        }),
        retryBaseDelay: Duration.zero,
        maxRetries: 2,
      );
      addTearDown(client.close);

      final HttpClientResponse res = await client.get(uri);
      expect(calls, 1);
      expect(res.statusCode, 404);
    });

    test('网络异常归一为 NetworkException', () async {
      final HttpClient client = HttpClient(
        inner: MockClient((http.Request req) async {
          throw http.ClientException('boom');
        }),
        retryBaseDelay: Duration.zero,
        maxRetries: 1,
      );
      addTearDown(client.close);

      await expectLater(
        client.get(uri),
        throwsA(isA<NetworkException>()),
      );
    });

    test('backoff 指数增长', () {
      final HttpClient client = HttpClient(
        retryBaseDelay: const Duration(milliseconds: 100),
      );
      addTearDown(client.close);
      expect(client.backoff(0), const Duration(milliseconds: 100));
      expect(client.backoff(1), const Duration(milliseconds: 200));
      expect(client.backoff(2), const Duration(milliseconds: 400));
    });

    test('响应对象 toString 含状态码与字节数', () async {
      final HttpClient client = HttpClient(
        inner: MockClient((http.Request req) async => http.Response('abc', 200)),
        retryBaseDelay: Duration.zero,
      );
      addTearDown(client.close);
      final HttpClientResponse res = await client.get(uri);
      expect(res.toString(), contains('200'));
      expect(res.toString(), contains('3B'));
    });
  });
}
