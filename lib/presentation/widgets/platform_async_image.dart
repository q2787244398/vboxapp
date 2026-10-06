/// 图片加载组件（批次 A · A-10，封面防盗链增强批次 H）。
///
/// 统一收敛封面/海报加载：**平台封面分支** + 占位态 / 加载态 / 失败态。
///
/// 封面防盗链机制（对齐 iOS `vbox/Services/PlatformImageLoader.swift`）：
///   · **`@key=value` 后缀解析** [parseHeaderSuffix]：TVBox 约定，图片 URL 可
///     携带 `@User-Agent=...@Referer=...@X-VBox-SSL-Bypass=1` 后缀，加载前拆出
///     干净 URL 与请求头（spider 返回的 `pic` 常见此格式，不透传则整串请求 404）；
///   · **`data:` 内嵌图**：spider 的 `pic` 可能直接返回 `data:image/png;base64,...`
///     （对齐 iOS `loadDataImage`），走 `Image.memory` 直接渲染；
///   · **默认 UA 注入**：存在自定义请求头但缺 `User-Agent` 时，注入桌面 Chrome
///     UA（对齐 iOS mysteryMovie 模式默认头）；
///   · **SSL 绕过**：检测到 `X-VBox-SSL-Bypass=1` 时走自定义 `HttpClient`
///     （`badCertificateCallback` 全放行，对齐 iOS `WelfareSSLBypassDelegate`）；
///   · 便捷工厂 [sourceCover]：按服务 `imageReferer` / `imageSSLBypass` 拼装
///     后缀（对齐 iOS `PlatformAsyncImage.sourceCover`）。
/// - URL 归一 [coverFor]：去空白、`http://`→`https://` 升迁（防混合内容拦截）。
/// - 缓存：Flutter `Image.network` / `Image.memory` 自带 `PaintingBinding.imageCache`，
///   本组件透传，不另建缓存层。
/// - 占位/失败态：默认「底 + 影片图标」占位盒（对齐 A-04 海报卡规格），
///   可注入自定义 [placeholder] / [errorBuilder]。
library;

import 'dart:convert' show base64Decode;
import 'dart:io' show HttpClient, HttpException, HttpClientRequest, HttpClientResponse;
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:flutter/material.dart';

import '../theme/tokens/typography.dart';

/// 平台图片默认 UA（对齐 iOS `PlatformImageLoader` mysteryMovie 桌面 Chrome UA）。
const String kPlatformImageDefaultUA =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

/// SSL 绕过标记头（对齐 iOS `@X-VBox-SSL-Bypass=1`）。
const String kPlatformImageSslBypassHeader = 'X-VBox-SSL-Bypass';

/// 豆瓣封面防盗链 Referer（对齐 iOS `DoubanImageProxyServer.fetchImage`）。
const String kDoubanImageReferer = 'https://movie.douban.com/';

/// 豆瓣 / TMDB 封面 CDN 主机（对齐 iOS `DoubanImageProxyServer.allowedHosts`）。
///
/// 这些 CDN 对直接请求返回 403（防盗链），iOS 端通过本地代理注入请求头解决；
/// Flutter 的 `Image.network` 原生支持请求头，命中主机时自动注入即可。
const Set<String> kDoubanImageHosts = <String>{
  'img1.doubanio.com',
  'img2.doubanio.com',
  'img3.doubanio.com',
  'img9.doubanio.com',
  'qnmob1.doubanio.com',
  'qnmob2.doubanio.com',
  'qnmob3.doubanio.com',
  'qnmob4.doubanio.com',
  'img1.douban.com',
  'img2.douban.com',
  'img3.douban.com',
  'img9.douban.com',
  'image.tmdb.org',
  'media.themoviedb.org',
};

/// [PlatformAsyncImage.parseHeaderSuffix] 解析结果：干净 URL + 请求头。
typedef ParsedImageUrl = ({String url, Map<String, String> headers});

/// 平台异步图片（网络加载 + 占位/失败兜底）。
class PlatformAsyncImage extends StatelessWidget {
  /// 构造。
  const PlatformAsyncImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholderColor,
    this.placeholder,
    this.errorBuilder,
    this.headers,
    this.imageDecoder,
    this.gaplessPlayback = true,
  });

  /// 图片地址（空 → 直接占位态，不发请求）。
  ///
  /// 支持 TVBox `@key=value` 后缀（[parseHeaderSuffix] 自动拆分）。
  final String? url;

  /// 填充方式。
  final BoxFit fit;

  /// 尺寸（缺省由父级约束决定）。
  final double? width;
  final double? height;

  /// 占位底（缺省取主题表面色）。
  final Color? placeholderColor;

  /// 自定义占位组件（缺省为「底 + 影片图标」）。
  final Widget? placeholder;

  /// 自定义失败态（缺省回退占位）。
  final Widget Function(BuildContext context, Object error, StackTrace? stackTrace)?
      errorBuilder;

  /// 显式请求头（优先级高于 URL 后缀同名键；空则纯透传 URL）。
  final Map<String, String>? headers;

  /// 字节后处理（非空 → 走「拉取字节 → 后处理 → 内存解码」路径）。
  ///
  /// 对齐 iOS `PlatformImageLoader` 的 `dailyBattle` 模式：每日大乱斗 / 每日大赛
  /// 的封面可能是 AES 加密字节，需先解密再交给图片解码器（见到非图片格式时
  /// 原样返回，避免破坏正常图片）。
  final Uint8List Function(Uint8List bytes)? imageDecoder;

  /// 网络图过渡（缺省 true，避免加载闪烁）。
  final bool gaplessPlayback;

  /// 平台封面分支：URL 归一。
  ///
  /// 返回 null 表示无有效地址（调用方直接走占位态，不发请求）。
  /// 现行为：去空白；`http://` 升迁 `https://`（防混合内容拦截）。
  static String? coverFor(String? url) {
    if (url == null) return null;
    final String trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://')) {
      return 'https://${trimmed.substring('http://'.length)}';
    }
    return trimmed;
  }

  /// 解码 `data:` 内嵌图（对齐 iOS `loadDataImage`）。
  ///
  /// 接受 `data:image/png;base64,<BASE64>`；非 `data:` 前缀或解码失败返回 null。
  static Uint8List? _embeddedDataImage(String raw) {
    if (!raw.startsWith('data:')) return null;
    final int comma = raw.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(raw.substring(comma + 1));
    } on FormatException {
      return null;
    }
  }

  /// 解析 `@key=value` 请求头后缀（对齐 iOS `PlatformImageLoader.parseHeaderSuffix`）。
  ///
  /// TVBox 约定：图片 URL 可携带 `@User-Agent=...@Referer=...` 后缀（spider 的
  /// `pic` 字段常见）。返回拆分后的干净 URL 与请求头；无后缀则原样透传。
  static ParsedImageUrl parseHeaderSuffix(String urlString) {
    final RegExp pattern = RegExp(r'@([^=]+)=([^@]+)');
    final List<RegExpMatch> matches = pattern.allMatches(urlString).toList();
    if (matches.isEmpty) {
      return (url: urlString, headers: const <String, String>{});
    }
    final Map<String, String> headers = <String, String>{};
    for (final RegExpMatch match in matches) {
      headers[match.group(1)!] = match.group(2)!;
    }
    return (
      url: urlString.substring(0, matches.first.start),
      headers: headers,
    );
  }

  /// 便捷工厂：按防盗链 Referer 拼装 UA / Referer / SSL 绕过后缀
  /// （对齐 iOS `PlatformAsyncImage.sourceCover`）。
  ///
  /// [referer] 为空则不附加任何请求头，等同普通加载；否则注入桌面 Chrome UA +
  /// Referer（自动补尾斜杠），并按 [sslBypass] 附 `X-VBox-SSL-Bypass=1`。
  static PlatformAsyncImage sourceCover(
    String url, {
    String? referer,
    bool sslBypass = false,
    BoxFit fit = BoxFit.fill,
    double? width,
    double? height,
    Widget? placeholder,
    Color? placeholderColor,
  }) {
    String finalUrl = url;
    if (referer != null && referer.isNotEmpty) {
      final String normalizedRef = referer.endsWith('/') ? referer : '$referer/';
      final String sslFlag = sslBypass ? '@$kPlatformImageSslBypassHeader=1' : '';
      finalUrl = '$url@User-Agent=$kPlatformImageDefaultUA'
          '@Referer=$normalizedRef$sslFlag';
    }
    return PlatformAsyncImage(
      url: finalUrl,
      fit: fit,
      width: width,
      height: height,
      placeholder: placeholder,
      placeholderColor: placeholderColor,
    );
  }

  /// 豆瓣 / TMDB 封面 CDN 自动注入的防盗链头（对齐 iOS
  /// `DoubanImageProxyServer.fetchImage`：`Referer: https://movie.douban.com/`
  /// + iPhone UA + Accept）。非命中主机返回空表，不影响其他图片。
  static Map<String, String> doubanHeadersFor(String urlString) {
    final Uri? uri = Uri.tryParse(urlString);
    final String? host = uri?.host.toLowerCase();
    if (host == null || !kDoubanImageHosts.contains(host)) {
      return const <String, String>{};
    }
    return <String, String>{
      'Referer': kDoubanImageReferer,
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    };
  }

  /// 默认占位盒（底 + 影片图标，对齐海报卡规格）。
  static Widget placeholderBox({required Color color}) => Container(
        color: color,
        alignment: Alignment.center,
        child: Icon(
          Icons.movie_outlined,
          size: VboxTypography.s24,
          color: Colors.white.withValues(alpha: 0.40),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color fallbackColor =
        placeholderColor ?? scheme.surfaceContainerHighest;
    final Widget fallback =
        placeholder ?? placeholderBox(color: fallbackColor);

    final String? raw = coverFor(url);
    if (raw == null) return fallback;

    // data: 内嵌图（对齐 iOS `loadDataImage`）：`data:image/png;base64,...`
    // 直接解码渲染，不走网络；解码失败回退占位。
    if (raw.startsWith('data:')) {
      final Uint8List? embedded = _embeddedDataImage(raw);
      if (embedded == null) return fallback;
      return Image.memory(
        embedded,
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: gaplessPlayback,
        errorBuilder: errorBuilder ??
            (BuildContext context, Object error, StackTrace? stackTrace) =>
                fallback,
      );
    }

    // 拆分 URL 后缀请求头（对齐 iOS parseHeaderSuffix），显式头优先覆盖。
    final ParsedImageUrl parsed = parseHeaderSuffix(raw);
    // 优先级：豆瓣/TMDB 防盗链默认头 < URL 后缀显式头 < 调用方 headers。
    final Map<String, String> merged = <String, String>{
      ...doubanHeadersFor(parsed.url),
      ...parsed.headers,
      if (headers != null) ...headers!,
    };
    // 自定义请求模式下注入默认 UA（对齐 iOS mysteryMovie 默认头）。
    if (merged.isNotEmpty && !merged.containsKey('User-Agent')) {
      merged['User-Agent'] = kPlatformImageDefaultUA;
    }
    // SSL 绕过 / 字节后处理 → 自定义 HttpClient（拉取字节后走 Image.memory）。
    final bool sslBypass = merged.remove(kPlatformImageSslBypassHeader) == '1';
    if (sslBypass || imageDecoder != null) {
      return _ByteFetchImage(
        url: parsed.url,
        headers: merged,
        sslBypass: sslBypass,
        transform: imageDecoder,
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: gaplessPlayback,
        fallback: fallback,
      );
    }

    return Image.network(
      parsed.url,
      fit: fit,
      width: width,
      height: height,
      headers: merged.isEmpty ? null : merged,
      gaplessPlayback: gaplessPlayback,
      errorBuilder: errorBuilder ??
          (BuildContext context, Object error, StackTrace? stackTrace) =>
              fallback,
      loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? p) {
        if (p == null) return child;
        return fallback;
      },
    );
  }
}

/// 字节拉取分支（SSL 全放行 + 可选字节后处理）：
/// 自定义 `HttpClient` 取字节 → [transform] 后处理 → `Image.memory`。
///
/// - `sslBypass`：对齐 iOS `WelfareSSLBypassDelegate`，全放行证书；
/// - `transform`：对齐 iOS `PlatformImageLoader` 的 `dailyBattle` 模式（AES 解密）。
class _ByteFetchImage extends StatefulWidget {
  const _ByteFetchImage({
    required this.url,
    required this.headers,
    required this.sslBypass,
    required this.fit,
    required this.gaplessPlayback,
    required this.fallback,
    this.transform,
    this.width,
    this.height,
  });

  final String url;
  final Map<String, String> headers;
  final bool sslBypass;
  final Uint8List Function(Uint8List bytes)? transform;
  final BoxFit fit;
  final double? width;
  final double? height;
  final bool gaplessPlayback;
  final Widget fallback;

  @override
  State<_ByteFetchImage> createState() => _ByteFetchImageState();
}

class _ByteFetchImageState extends State<_ByteFetchImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final HttpClient client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 15);
    if (widget.sslBypass) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    try {
      final HttpClientRequest request =
          await client.getUrl(Uri.parse(widget.url));
      for (final MapEntry<String, String> entry in widget.headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final HttpClientResponse response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}',
            uri: Uri.parse(widget.url));
      }
      final BytesBuilder builder = BytesBuilder(copy: false);
      await for (final List<int> chunk in response) {
        builder.add(chunk);
      }
      Uint8List bytes = builder.takeBytes();
      final Uint8List Function(Uint8List bytes)? transform = widget.transform;
      if (transform != null) bytes = transform(bytes);
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = _bytes;
    if (bytes == null || _failed) return widget.fallback;
    return Image.memory(
      bytes,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: widget.gaplessPlayback,
      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
          widget.fallback,
    );
  }
}
