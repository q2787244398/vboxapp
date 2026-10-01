/// 图片加载组件（批次 A · A-10）。
///
/// 统一收敛封面/海报加载：**平台封面分支** + 占位态 / 加载态 / 失败态。
///
/// - 平台封面分支 [coverFor]：URL 归一（去空白、`http://`→`https://` 升迁，
///   防混合内容被平台拦截），其余原样透传。后续平台差异（如豆瓣/网盘封面
///   加 headers）在此扩展。
/// - 缓存：Flutter `Image.network` 自带 `PaintingBinding.imageCache`，本组件
///   透传，不另建缓存层。
/// - 占位/失败态：默认「底 + 影片图标」占位盒（对齐 A-04 海报卡规格），
///   可注入自定义 [placeholder] / [errorBuilder]。
library;

import 'package:flutter/material.dart';

import '../theme/tokens/typography.dart';

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
    this.gaplessPlayback = true,
  });

  /// 图片地址（空 → 直接占位态，不发请求）。
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

  /// 请求头（平台封面差异扩展点）。
  final Map<String, String>? headers;

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

    final String? resolved = coverFor(url);
    if (resolved == null) return fallback;

    return Image.network(
      resolved,
      fit: fit,
      width: width,
      height: height,
      headers: headers,
      gaplessPlayback: gaplessPlayback,
      errorBuilder: errorBuilder ??
          (BuildContext context, Object error, StackTrace? stackTrace) => fallback,
      loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? p) {
        if (p == null) return child;
        return fallback;
      },
    );
  }
}