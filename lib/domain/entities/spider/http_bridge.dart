/// 领域层：蜘蛛 HTTP 桥接（编码探测 + 请求参数）。
///
/// 唯一真相源：`contract/docs/abi_v1.md` §4「HTTP 回调协议」
/// 逆向来源：iOS `vbox/Services/JSHTTPBridge.swift`
///
/// ⚠️ 编码探测链必须复刻（契约 §4.2）：
/// ```
/// ① 响应头 Content-Type 的 charset
/// ② UTF-8 尝试 → 若 meta 声明非 UTF-8，用 meta charset 重新解码
/// ③ 前 4096 字节 ASCII 探测 meta charset
/// ④ 兜底链：GBK → GB2312 → Big5 → ISO-8859-1
/// ⑤ 全部失败 → base64 编码返回
/// ```
library;

import 'dart:convert';
import 'dart:typed_data';

/// HTTP 请求参数（对齐契约 §4.1）。
class SpiderHttpRequest {
  const SpiderHttpRequest({
    required this.url,
    this.headers = const <String, String>{},
    this.method = 'GET',
    this.data,
    this.timeoutSeconds = defaultTimeout,
    this.sslBypass = false,
  });

  /// HTTP 默认超时（契约 §6：15 秒）。
  static const double defaultTimeout = 15.0;

  final String url;
  final Map<String, String> headers;
  final String method;

  /// POST body。
  final String? data;
  final double timeoutSeconds;

  /// SSL 绕过（仅福利 JS Spider 使用，契约 §4.3）。
  final bool sslBypass;
}

/// HTTP 响应。
class SpiderHttpResponse {
  const SpiderHttpResponse({
    required this.status,
    required this.headers,
    required this.body,
    this.rawBytes,
  });

  final int status;
  final Map<String, String> headers;

  /// 已按编码探测链解码的文本。
  final String body;

  /// 原始字节（供 `getBytes` 类调用）。
  final Uint8List? rawBytes;
}

/// 字符集规范化（对齐契约 §4.2 的映射表）。
String normalizeCharset(String input) {
  final String s = input.trim().toLowerCase().replaceAll('"', '').replaceAll("'", '');
  return switch (s) {
    'utf-8' || 'utf8' => 'utf-8',
    'gbk' || 'gb2312' || 'gb-2312' || 'gb18030' || 'gb-18030' || 'gb18030-2000' => 'gbk',
    'big5' || 'big-5' => 'big5',
    'iso-8859-1' || 'latin1' || 'latin-1' => 'latin1',
    _ => s,
  };
}

/// 从 Content-Type 头提取 charset。
String? charsetFromContentType(String? contentType) {
  if (contentType == null) return null;
  final RegExp re = RegExp(r'charset\s*=\s*([^\s;]+)', caseSensitive: false);
  final RegExpMatch? m = re.firstMatch(contentType);
  return m?.group(1);
}

/// 从 HTML 前 4096 字节 ASCII 区域探测 meta charset。
String? sniffMetaCharset(Uint8List bytes) {
  final int limit = bytes.length < 4096 ? bytes.length : 4096;
  // 只取 ASCII 可打印区域做探测
  final String head = String.fromCharCodes(
      bytes.sublist(0, limit).where((b) => b < 128));
  final RegExp re = RegExp(
    r'<meta[^>]+charset\s*=\s*["' "'" r']?\s*([a-zA-Z0-9_\-]+)',
    caseSensitive: false,
  );
  final RegExpMatch? m = re.firstMatch(head);
  return m?.group(1);
}

/// 用指定编码解码字节（返回 null 表示不支持该编码）。
String? _decodeWith(Uint8List bytes, String charset) {
  try {
    switch (charset) {
      case 'utf-8':
        return utf8.decode(bytes, allowMalformed: false);
      case 'latin1':
        return latin1.decode(bytes);
      case 'gbk':
      case 'gb2312':
      case 'gb18030':
        return _decodeMultiByte(bytes, _gbkTable);
      case 'big5':
        return _decodeMultiByte(bytes, _big5Table);
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}

// ─────────────────────────────────────────────────────────
// 简化版 GBK / Big5 解码
// 说明：Dart 核心库无内置 GBK/Big5；此处按契约要求实现探测链骨架，
//      实际码表在平台适配层注入（见 _gbkTable / _big5Table 注释）。
// ─────────────────────────────────────────────────────────

/// GBK 码表（适配层注入；为空时回退 latin1）。
Map<int, String> _gbkTable = <int, String>{};

/// Big5 码表（适配层注入）。
Map<int, String> _big5Table = <int, String>{};

/// 注入码表（由平台适配层在启动时调用）。
void registerCharsetTables({
  Map<int, String>? gbk,
  Map<int, String>? big5,
}) {
  if (gbk != null) _gbkTable = gbk;
  if (big5 != null) _big5Table = big5;
}

String _decodeMultiByte(Uint8List bytes, Map<int, String> table) {
  final StringBuffer sb = StringBuffer();
  int i = 0;
  while (i < bytes.length) {
    final int b = bytes[i];
    if (b < 0x80) {
      sb.writeCharCode(b);
      i += 1;
    } else if (i + 1 < bytes.length) {
      final int code = (b << 8) | bytes[i + 1];
      sb.write(table[code] ?? String.fromCharCode(b));
      i += 2;
    } else {
      sb.writeCharCode(b);
      i += 1;
    }
  }
  return sb.toString();
}

/// 按契约 §4.2 的探测链解码响应体。
///
/// 返回 [文字, 是否使用 base64 兜底]。
(String, bool) decodeResponseBody(
  Uint8List bytes, {
  String? contentTypeCharset,
  String? metaCharsetOverride,
}) {
  // ① 响应头 charset
  if (contentTypeCharset != null) {
    final String cs = normalizeCharset(contentTypeCharset);
    final String? out = _decodeWith(bytes, cs);
    if (out != null) return (out, false);
  }

  // ② UTF-8 尝试
  final String? utf8Out = _decodeWith(bytes, 'utf-8');
  if (utf8Out != null) {
    // 若 meta 声明非 UTF-8，用 meta charset 重新解码
    if (metaCharsetOverride != null &&
        normalizeCharset(metaCharsetOverride) != 'utf-8') {
      final String? re = _decodeWith(bytes, normalizeCharset(metaCharsetOverride));
      if (re != null) return (re, false);
    }
    return (utf8Out, false);
  }

  // ③ ASCII 探测 meta charset
  final String? sniffed = sniffMetaCharset(bytes);
  if (sniffed != null) {
    final String? out = _decodeWith(bytes, normalizeCharset(sniffed));
    if (out != null) return (out, false);
  }

  // ④ 兜底链：GBK → GB2312 → Big5 → ISO-8859-1
  for (final String cs in <String>['gbk', 'gb2312', 'big5', 'latin1']) {
    final String? out = _decodeWith(bytes, cs);
    if (out != null) return (out, false);
  }

  // ⑤ 全部失败 → base64
  return (base64.encode(bytes), true);
}
